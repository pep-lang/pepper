//
// Created by Justin Boswell on 12/26/22.
//

#include "AST/Functions.h"
#include "AST/Literals.h"
#include "AST/Struct.h"
#include "CodeGenerator.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Frontend/LLVMUtils.h"
#include "Frontend/Operations.h"
#include "Frontend/Struct.h"
#include "Frontend/Types.h"

namespace pepper {
    using namespace pepper::ast;

    Address CodeGenerator::emit(Ref<FieldDef> fieldDef) {
        auto st = Struct::get(fieldDef->Struct->Name);
        auto instance = locals()->findSymbol("this");
        instance = load(instance);
        auto fieldName = fieldDef->Name;
        auto field = st->getField(instance, fieldName);
        if (!field) {
            throw CompileError(
                fieldDef->Source, "struct {0} does not contain a field named {1}", st->name(), fieldName);
        }
        auto type = Types::get(fieldDef->Type.toString());
        auto value = maybeCodegen(fieldDef->Default);
        if (value) {
            type->ops()->init(field, value);
        } else {
            value = zeroValue(type);
            ir()->CreateStore(value, field);
        }

        return Address{type, field};
    }

    Address CodeGenerator::emit(Ref<MemberRef> memberRef) {
        auto local = locals()->findSymbol(memberRef->Name, true);
        if (local)
            return local;

        auto lhs = codegen(memberRef->LHS);
        auto lhsType = lhs.Ty;
        auto structDesc = Struct::get(lhsType->name());
        auto memberName = memberRef->Name;
        auto field = Query(structDesc->fields()).find([&memberName](auto f) { return f.Name == memberName; }).value();
        auto thisPtr = load(lhs);
        auto member = Address{field.Type, structDesc->getMember(thisPtr, memberName), memberName};
        return member;
    }

    void CodeGenerator::instantiate(Ref<ast::StructDef> structDef) {
        // Generic struct bases are effectively abstract, so can't be instantiated
        if (!structDef->GenericParams.empty()) {
            return;
        }

        // convert fields to symbols before type gen
        pepper::Params fields;
        for (auto& field : structDef->Fields) {
            auto type = Types::get(field->Type.toString());
            fields.emplace_back(field->Name, type);
        }

        auto ctorParams = Query(structDef->Constructor->Parameters).select<pepper::Param>([this](auto p) {
            return pepper::Param{p.Name, Types::get(p.Type.toString()), maybeCodegen(p.Default)};
        });

        // generate the new struct type
        auto structDesc = Struct::New(Module->getModule(), structDef->Name, fields, ctorParams);
        auto structDI = Module->getDebugInfo()->emitStruct(structDesc.get());
        Module->getDebugInfo()->pushScope(structDI);

        // Update Struct()/new function now that the size of the struct is known
        auto sizeVar = Query(structDef->Constructor->Body->Items)
                           .find([](auto& local) {
                               if (local->template is<VariableDef>()) {
                                   auto var = local.template as<VariableDef>();
                                   return var->Name == "size";
                               }
                               return false;
                           })
                           .value()
                           .as<VariableDef>();
        sizeVar->Default = Ref<IntegerLiteral>::New(structDesc->size());

        // Export new constructor to the enclosing scope
        locals()->newFunction(structDesc->constructor());

        // map method names to mangled free functions while maintaining order
        Vector<Ref<Method>> methods;
        for (auto& method : structDef->Methods) {
            auto realName = method->Name;
            pepper::Params params;
            // inject this pointer
            auto thisType = Types::get(structDef->Name);
            params.emplace_back("this", thisType);
            for (auto& paramDef : method->Parameters) {
                auto type = Types::get(paramDef.Type.toString());
                params.emplace_back(paramDef.Name, type, maybeCodegen(paramDef.Default));
            }
            // TODO: mangle these properly
            auto mangledName = structDef->Name + "." + realName;
            auto returnType = Types::get(method->ReturnType.toString());
            auto newMethod = Ref<Method>::New(Module->getModule(), structDesc, mangledName, returnType, params);
            methods.push_back(newMethod);
            structDesc->addMethod(newMethod, realName);
        }

        Module->getDebugInfo()->popScope();

        PEP_TRACE(TraceChannel::Codegen,
                  "StructDef {0} -> {1}",
                  structDef->Name,
                  toString(structDesc->structType()->llvmType()));
    }

    void CodeGenerator::codegenStruct(Ref<StructDef> structDef) {
        // Generic struct bases are effectively abstract, so can't be instantiated
        if (!structDef->GenericParams.empty()) {
            return;
        }

        auto structDesc = Struct::get(structDef->Name);

        auto structDI = Module->getDebugInfo()->getStruct(structDesc.get());
        assert(structDI && "emit called without first calling instantiate");
        Module->getDebugInfo()->pushScope(structDI);

        codegenFunction(structDesc->constructor(), structDef->Constructor);

        const auto& methods = structDef->Methods;
        for (int methodIdx = 0; methodIdx < methods.size(); ++methodIdx) {
            const auto& methodDef = methods[methodIdx];
            auto method = structDesc->method(methodDef->Name);
            assert(method && "MethodDef was not instantiated before codegen");
            codegenFunction(method, methodDef);
        }

        Module->getDebugInfo()->popScope();
    }

    Address CodeGenerator::emit(Ref<ThisDef> thisDef) {
        auto typeName = thisDef->Type;
        auto type = Types::get(typeName.toString());
        if (!type) {
            throw CompileError(thisDef->Source, "Unknown type for this: {0}", typeName.toString());
        }
        auto value = Address(type, ir()->CreateAlloca(*type, nullptr, "this"), "this");
        if (!thisDef->Hidden)
            Module->getDebugInfo()->emitLocalVariable(value);
        auto defaultValue = maybeCodegen(thisDef->Default);
        if (!defaultValue)
            throw InternalCompilerError("{0} this does not have an initial value", typeName.toString());
        // Intentionally skip assign/init, to avoid refcount/order shenanigans
        ir()->CreateStore(defaultValue, value);
        locals()->newSymbol(value);
        return value;
    }

    Address CodeGenerator::emit(Ref<ThisRef>) {
        auto thisPtr = locals()->findSymbol("this");
        return thisPtr;
    }

    Address CodeGenerator::emit(Ref<MethodCall> call) {
        auto thisRef = codegen(call->This);
        auto st = Struct::get(thisRef.Ty->name());
        auto method = st->method(call->Name).as<Method>();
        if (!method) {
            throw CompileError("Method {0} not found", call->Name);
        }
        Vector<Address> args;
        thisRef = load(thisRef);
        args.push_back(thisRef);

        const auto& callArgs = call->Args;
        for (const auto& argExpr : callArgs) {
            args.push_back(codegen(argExpr));
        }
        return Address{method->returnType(), method->call(args)};
    }
} // namespace pepper
