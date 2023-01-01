//
// Created by Justin Boswell on 12/26/22.
//

#include "Codegen/Struct.h"

#include "AST/Functions.h"
#include "AST/Literals.h"
#include "AST/Struct.h"
#include "Codegen/Context.h"
#include "Codegen/IR/Codegen.h"
#include "Codegen/LLVMUtils.h"
#include "Codegen/Types.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"

namespace pepper {
    using namespace pepper::ast;

    Value Codegen::emit(Ref<FieldDef> fieldDef) {
        auto st = Struct::get(fieldDef->Struct->Identifier);
        auto instance = Context::get().locals()->findSymbol("this");
        instance = read(instance);
        auto fieldName = fieldDef->Identifier;
        auto field = st->getField(instance, fieldName);
        if (!field) {
            throw CompileError("struct {0} does not contain a field named {1}", st->name(), fieldName);
        }
        auto type = Types::get(fieldDef->Type);
        auto value = maybeCodegen(fieldDef->Default);
        if (!value) {
            value = zeroValue(type);
        }
        ir()->CreateStore(value, field);
        return Value(type, field);
    }

    Value Codegen::emit(Ref<MemberRef> memberRef) {
        auto lhs = codegen(memberRef->LHS);
        auto lhsType = lhs.Ty;
        auto structDesc = Struct::get(lhsType->name());
        auto memberName = memberRef->MemberName;
        auto field =
            Query(structDesc->fields()).find([&memberName](auto f) { return f.ParamName == memberName; }).value();
        auto thisPtr = read(lhs);
        auto member = structDesc->getMember(thisPtr, memberName);
        return Value(field.ParamType, member);
    }

    Ref<Struct> Codegen::emit(Ref<StructDef> structDef) {
        // convert fields to symbols before type gen
        pepper::Params fields;
        Vector<llvm::Type*> fieldTypes;
        for (auto& field : structDef->Fields) {
            auto type = Types::get(field->Type);
            fieldTypes.push_back(*type);
            fields.emplace_back(field->Identifier, type);
        }

        // generate the new struct type
        auto llvmType = llvm::StructType::create(fieldTypes, structDef->Identifier);
        auto structType = Types::add(Ref<TypeInfo>::New(structDef->Identifier, llvmType));
        auto structPtrType = Types::get(structDef->Identifier);
        auto structDesc = Struct::New(structType, structDef->Identifier);
        structDesc->setFields(fields);

        // Update Struct()/new function now that the size of the struct is known
        auto sizeVar = Query(structDef->NewInstance->Body->Items)
                           .find([](auto& local) {
                               if (local->template is<VariableDef>()) {
                                   auto var = local.template as<VariableDef>();
                                   return var->Identifier == "size";
                               }
                               return false;
                           })
                           .value()
                           .as<VariableDef>();
        sizeVar->Default = Ref<IntegerLiteral>::New(structDesc->size());

        // Export new function to the enclosing scope
        Context::get().locals()->newFunction(structDesc->instanceNew());

        // map method names to mangled free functions while maintaining order
        Vector<Ref<Method>> methods;
        for (auto& method : structDef->Methods) {
            auto realName = method->Identifier;
            pepper::Params params;
            // inject this pointer
            auto thisType = Types::get(structDef->Identifier);
            params.emplace_back("this", thisType);
            for (auto& paramDef : method->Parameters) {
                auto type = Types::get(paramDef.Type);
                params.emplace_back(paramDef.Identifier, type, maybeCodegen(paramDef.Default));
            }
            // TODO: mangle these properly
            auto mangledName = structDef->Identifier + "." + realName;
            auto returnType = Types::get(method->ReturnType);
            auto newMethod = Ref<Method>::New(structDesc, mangledName, returnType, params);
            methods.push_back(newMethod);
            structDesc->addMethod(newMethod, realName);
        }

        for (int methodIdx = 0; methodIdx < methods.size(); ++methodIdx) {
            auto& method = methods[methodIdx];
            auto& methodDef = structDef->Methods[methodIdx];
            codegenFunction(method, methodDef);
        }

        codegenFunction(structDesc->instanceNew(), structDef->NewInstance);
        PEP_TRACE(TraceChannel::Codegen,
                  "StructDef {0} -> {1}",
                  structDef->Identifier,
                  toString(structDesc->type()->llvmType()));
        return structDesc;
    }

    Value Codegen::emit(Ref<ThisRef> thisRef) {
        auto thisPtr = Context::get().locals()->findSymbol("this");
        return thisPtr;
    }

    Value Codegen::emit(Ref<MethodCall> call) {
        auto thisRef = codegen(call->This);
        auto st = Struct::get(thisRef.Ty->name());
        auto method = st->method(call->MethodName).as<Method>();
        if (!method) {
            throw CompileError("Method {0} not found", call->MethodName);
        }
        Vector<Value> args;
        thisRef = read(thisRef);
        args.push_back(thisRef);

        const auto& callArgs = call->Args;
        for (auto argExpr : callArgs) {
            args.push_back(codegen(argExpr));
        }
        return Value(method->returnType(), method->call(args));
    }
} // namespace pepper
