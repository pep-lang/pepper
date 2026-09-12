

#include "CodeGen/LLVM/LLVMCodeGenerator.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Core/Messages.h"
#include "Sema/Model/Functions.h"
#include "Sema/Model/Literals.h"
#include "Sema/Model/Struct.h"
#include "Sema/Operations.h"
#include "Sema/Struct.h"
#include "Sema/Types.h"

namespace pepper {

    Address LLVMCodeGenerator::emit(const sema::FieldDef* fieldDef) {
        auto st = Struct::get(fieldDef->parent.name());
        assert(st && "Field attached to non-existent struct");
        auto instance = locals()->find_symbol("this");
        instance = load(instance);
        auto fieldName = fieldDef->name;
        auto field = st->get_field(instance, fieldName);
        if (!field) {
            throw CompileError(
                fieldDef->source_loc, "struct {0} does not contain a field named {1}", st->name(), fieldName);
        }
        auto type = Types::get(fieldDef->type.to_string());
        if (!type)
            throw CompileError(
                fieldDef->source_loc, "Unknown type for field {0}: {1}", fieldDef->name, fieldDef->type.to_string());
        auto value = maybeCodegen(fieldDef->default_value);
        if (value) {
            type->ops()->init(field, value);
        } else {
            value = zero_value(type);
            ir()->CreateStore(value, field);
        }

        return Address{type, field};
    }

    Address LLVMCodeGenerator::emit(const sema::MemberRef* memberRef) {
        auto local = locals()->find_symbol(memberRef->id, true);
        if (local)
            return local;

        auto lhs = codegen(memberRef->lhs);
        auto lhsType = lhs.type;
        auto structDesc = Struct::get(lhsType->name());
        auto memberName = memberRef->id;
        auto field = Query(structDesc->fields()).find([&memberName](auto f) { return f.name == memberName; }).value();
        auto thisPtr = load(lhs);
        auto member = Address{field.type, structDesc->get_member(thisPtr, memberName), memberName};
        return member;
    }

    void LLVMCodeGenerator::instantiate(const sema::StructDef* structDef) {
        // Generic struct bases are effectively abstract, so can't be instantiated
        if (structDef->is_generic()) {
            return;
        }

        PEP_TRACE(TraceChannel::Codegen, "  Instantiating {0}", structDef->name);

        // convert fields to symbols before type gen
        pepper::Params fields;
        for (auto& field : structDef->field_members) {
            auto type = Types::get(field->type.to_string());
            if (!type)
                throw CompileError(
                    field->source_loc, "Field {0} has unknown type {1}", field->name, field->type.to_string());
            fields.emplace_back(field->name, type);
        }

        auto ctorParams = Query(structDef->construct->parameters).select<pepper::Param>([this](auto p) {
            return pepper::Param{p.name, Types::get(p.type.to_string()), maybeCodegen(p.default_value)};
        });

        // generate the new struct type
        auto structDesc = Struct::create(module->get_llvm_module(), structDef->name, fields, ctorParams);
        auto structDI = module->get_debug_info()->emitStruct(structDesc.get());
        module->get_debug_info()->push_scope(structDI);

        // Update Struct()/new function now that the size of the struct is known
        for (auto& local : structDef->construct->body->items) {
            if (local->template is<sema::VariableDef>()) {
                auto var = local->template as<sema::VariableDef>();
                if (var->name == "size") {
                    sema::Node::push_source(structDef->source_loc);
                    var->default_value = new sema::IntegerLiteral(structDesc->size());
                    sema::Node::pop_source();
                    break;
                }
            }
        }

        // Export new constructor to the enclosing scope
        locals()->function(structDesc->constructor());

        module->get_debug_info()->pop_scope();

        PEP_TRACE(TraceChannel::Codegen,
                  "StructDef {0} -> {1}",
                  structDef->name,
                  to_string(Types::get(structDesc->type().get())));
    }

    void LLVMCodeGenerator::instantiateMethods(const sema::StructDef* structDef) {
        // Generic struct bases are effectively abstract, so can't be instantiated
        if (structDef->is_generic()) {
            return;
        }

        auto structDesc = Struct::get(structDef->name);
        auto structDI = module->get_debug_info()->getStruct(structDesc.get());
        module->get_debug_info()->push_scope(structDI);

        Messages::indent(TraceChannel::Codegen);

        // map method names to mangled free functions while maintaining order
        Vector<Ref<Method>> method_members;
        for (auto& method : structDef->method_members) {
            auto realName = method->name;
            pepper::Params params;
            if (!method->is_static()) {
                // inject this pointer
                auto thisType = Types::get(structDef->name);
                params.emplace_back("this", thisType);
            }
            for (auto& paramDef : method->parameters) {
                auto type = Types::get(paramDef.type.to_string());
                params.emplace_back(paramDef.name, type, maybeCodegen(paramDef.default_value));
            }
            // TODO: mangle these properly
            auto mangledName = structDef->name + "." + realName;
            auto return_type = Types::get(method->return_type.to_string());

            PEP_TRACE(TraceChannel::Codegen, method->to_string());

            auto newMethod = Ref<Method>::create(module->get_llvm_module(), structDesc, mangledName, return_type, params);
            method_members.push_back(newMethod);
            structDesc->add_method(newMethod, realName);
        }

        Messages::outdent(TraceChannel::Codegen);

        module->get_debug_info()->pop_scope();
    }

    void LLVMCodeGenerator::codegenStruct(const sema::StructDef* structDef) {
        // Generic struct bases are effectively abstract, so can't be instantiated
        if (structDef->is_generic()) {
            return;
        }

        auto structDesc = Struct::get(structDef->name);

        auto structDI = module->get_debug_info()->getStruct(structDesc.get());
        assert(structDI && "emit called without first calling instantiate");
        module->get_debug_info()->push_scope(structDI);

        codegenFunction(structDesc->constructor(), structDef->construct);

        for (const auto& methodDef : structDef->method_members) {
            auto method = structDesc->method(methodDef->name);
            assert(method && "MethodDef was not instantiated before codegen");
            codegenFunction(method, methodDef);
        }

        module->get_debug_info()->pop_scope();
    }

    Address LLVMCodeGenerator::emit(const sema::ThisDef* thisDef) {
        auto typeName = thisDef->type;
        auto type = Types::get(typeName.to_string());
        if (!type) {
            throw CompileError(thisDef->source_loc, "Unknown type for this: {0}", typeName.to_string());
        }
        auto value = Address(type, ir()->CreateAlloca(*type, nullptr, "this"), "this");
        if (!thisDef->is_hidden)
            module->get_debug_info()->emitLocalVariable(value);
        auto defaultValue = maybeCodegen(thisDef->default_value);
        if (!defaultValue)
            throw InternalCompilerError("{0} this does not have an initial value", typeName.to_string());
        // Intentionally skip assign/init, to avoid refcount/order shenanigans
        ir()->CreateStore(defaultValue, value);
        locals()->symbol(value);
        return value;
    }

    Address LLVMCodeGenerator::emit(const sema::ThisRef*) {
        auto thisPtr = locals()->find_symbol("this");
        return thisPtr;
    }

    Address LLVMCodeGenerator::emit(const sema::MethodCall* call) {
        Vector<Address> args;

        if (!call->Target->is_static()) {
            auto thisRef = codegen(call->This);
            thisRef = load(thisRef);
            args.push_back(thisRef);
        }

        auto st = Struct::get(call->Target->parent->name);
        auto method = st->method(call->Target.to_string());
        if (!method) {
            throw CompileError("Method {0} not found", call->Target.to_string());
        }

        const auto& callArgs = call->Args;
        for (const auto& argExpr : callArgs) {
            args.push_back(codegen(argExpr));
        }
        return Address{method->return_type(), method->call(args)};
    }
} // namespace pepper
