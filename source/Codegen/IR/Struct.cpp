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
        auto st = Struct::get(fieldDef->Struct->identifier());
        auto instance = Context::get().locals()->findSymbol("this");
        instance = read(instance);
        auto fieldName = fieldDef->identifier();
        auto field = st->getField(instance, fieldName);
        if (!field) {
            throw CompileError("struct {0} does not contain a field named {1}", st->name(), fieldName);
        }
        auto type = Types::get(fieldDef->type());
        auto value = maybeCodegen(fieldDef->defaultValue());
        if (!value) {
            value = zeroValue(type);
        }
        ir()->CreateStore(value, field);
        return Value(type, field);
    }

    Ref<Function> Codegen::resolveFunction(Ref<FunctionCall> call) {
        auto functionName = call->target()->identifier();
        auto target = call->target();
        if (target->is<MethodDef>()) {
            auto methodDef = target.as<MethodDef>();
            auto st = methodDef->structDef();
            auto name = methodDef->identifier();
            auto mangledName = st->identifier() + "." + name;
            functionName = mangledName;
        }
        return Context::get().locals()->findFunction(functionName);
    }

    Value Codegen::emit(Ref<MemberRef> memberRef) {
        auto lhs = codegen(memberRef->lhs());
        auto lhsType = lhs.Ty;
        auto structDesc = Struct::get(lhsType->name());
        auto memberName = memberRef->name();
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
            auto type = Types::get(field->type());
            fieldTypes.push_back(*type);
            fields.emplace_back(field->identifier(), type);
        }

        // generate the new struct type
        auto llvmType = llvm::StructType::create(fieldTypes, structDef->identifier());
        auto structType = Types::add(Ref<TypeInfo>::New(structDef->identifier(), llvmType));
        auto structPtrType = Types::get(structDef->identifier());
        auto structDesc = Struct::New(structType, structDef->identifier());
        structDesc->setFields(fields);

        // Update Struct()/new function now that the size of the struct is known
        auto sizeVar = std::find_if(structDef->NewInstance->locals().begin(),
                                    structDef->NewInstance->locals().end(),
                                    [](auto& local) { return (local->identifier() == "size"); });
        assert(sizeVar != structDef->NewInstance->locals().end());
        (*sizeVar)->setDefaultValue(Ref<IntegerLiteral>::New(structDesc->size()));

        // Export new function to the enclosing scope
        Context::get().locals()->newFunction(structDesc->instanceNew());

        // map method names to mangled free functions while maintaining order
        Vector<Ref<Method>> methods;
        for (auto& method : structDef->Methods) {
            auto realName = method->identifier();
            pepper::Params params;
            // inject this pointer
            auto thisType = Types::get(structDef->identifier());
            params.emplace_back("this", thisType);
            for (auto& paramDef : method->params()) {
                auto type = Types::get(paramDef.Type);
                params.emplace_back(paramDef.Identifier, type, maybeCodegen(paramDef.Default));
            }
            // TODO: mangle these properly
            auto mangledName = structDef->identifier() + "." + realName;
            auto returnType = Types::get(method->returnType());
            auto newMethod = Ref<Method>::New(mangledName, returnType, params);
            methods.push_back(newMethod);
            structDesc->addMethod(newMethod);
        }

        for (int methodIdx = 0; methodIdx < methods.size(); ++methodIdx) {
            auto& method = methods[methodIdx];
            auto& methodDef = structDef->Methods[methodIdx];
            codegenFunction(method, methodDef);
        }

        codegenFunction(structDesc->instanceNew(), structDef->NewInstance);
        PEP_TRACE(TraceChannel::Codegen,
                  "StructDef {0} -> {1}",
                  structDef->identifier(),
                  toString(structDesc->type()->llvmType()));
        return structDesc;
    }

    Value Codegen::emit(Ref<ThisRef> thisRef) {
        auto thisPtr = Context::get().locals()->findSymbol("this");
        return thisPtr;
    }
} // namespace pepper
