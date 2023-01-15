//
// Created by Justin Boswell on 12/26/22.
//

#include "AST/Functions.h"
#include "AST/Literals.h"
#include "AST/Struct.h"
#include "Codegen.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Frontend/LLVMUtils.h"
#include "Frontend/Struct.h"
#include "Frontend/TypeOps.h"
#include "Frontend/Types.h"

namespace pepper {
    using namespace pepper::ast;

    Value Codegen::emit(Ref<FieldDef> fieldDef) {
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

        return Value{type, field};
    }

    Value Codegen::emit(Ref<MemberRef> memberRef) {
        auto local = locals()->findSymbol(memberRef->Name, true);
        if (local)
            return local;

        auto lhs = codegen(memberRef->LHS);
        auto lhsType = lhs.Ty;
        auto structDesc = Struct::get(lhsType->name());
        auto memberName = memberRef->Name;
        auto field = Query(structDesc->fields()).find([&memberName](auto f) { return f.Name == memberName; }).value();
        auto thisPtr = load(lhs);
        auto member = Value{field.Type, structDesc->getMember(thisPtr, memberName), memberName};
        // LHS may have moved or unset source location, so restore it
        Module->getDebugInfo()->setSourceLocation(memberRef->Source);
        locals()->newSymbol(member);
        return member;
    }

    void Codegen::emit(Ref<StructDef> structDef) {
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
        auto structDesc = Struct::New(structDef->Name, fields, ctorParams);
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
        codegenFunction(structDesc->constructor(), structDef->Constructor);

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
            auto newMethod = Ref<Method>::New(structDesc, mangledName, returnType, params);
            methods.push_back(newMethod);
            structDesc->addMethod(newMethod, realName);
        }

        for (int methodIdx = 0; methodIdx < methods.size(); ++methodIdx) {
            auto& method = methods[methodIdx];
            auto& methodDef = structDef->Methods[methodIdx];
            codegenFunction(method, methodDef);
        }

        Module->getDebugInfo()->popScope();

        PEP_TRACE(TraceChannel::Codegen,
                  "StructDef {0} -> {1}",
                  structDef->Name,
                  toString(structDesc->structType()->llvmType()));
    }

    Value Codegen::emit(Ref<ThisDef> thisDef) {
        auto typeName = thisDef->Type;
        auto type = Types::get(typeName.toString());
        if (!type) {
            throw CompileError(thisDef->Source, "Unknown type for this: {0}", typeName.toString());
        }
        auto value = Value(type, ir()->CreateAlloca(*type, nullptr, "this"), "this");
        auto defaultValue = maybeCodegen(thisDef->Default);
        if (!defaultValue)
            throw InternalCompilerError("{0} this does not have an initial value", typeName.toString());
        // Intentionally skip assign/init, to avoid refcount/order shenanigans
        ir()->CreateStore(defaultValue, value);
        locals()->newSymbol(value);
        return value;
    }

    Value Codegen::emit(Ref<ThisRef>) {
        auto thisPtr = locals()->findSymbol("this");
        return thisPtr;
    }

    Value Codegen::emit(Ref<MethodCall> call) {
        auto thisRef = codegen(call->This);
        auto st = Struct::get(thisRef.Ty->name());
        auto method = st->method(call->Name).as<Method>();
        if (!method) {
            throw CompileError("Method {0} not found", call->Name);
        }
        Vector<Value> args;
        thisRef = load(thisRef);
        args.push_back(thisRef);

        const auto& callArgs = call->Args;
        for (const auto& argExpr : callArgs) {
            args.push_back(codegen(argExpr));
        }
        return Value{method->returnType(), method->call(args)};
    }
} // namespace pepper
