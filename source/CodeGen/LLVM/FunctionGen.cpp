

#include "CodeGen/LLVM/LLVMCodeGenerator.h"
#include "Core/Exceptions.h"
#include "Core/LLVMUtils.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "Sema/Function.h"
#include "Sema/Model/Functions.h"
#include "Sema/Operations.h"
#include "Sema/Types.h"

namespace pepper {
    using namespace pepper::sema;

    Ref<Function> LLVMCodeGenerator::resolveFunction(const FunctionCall* call) {
        auto functionName = call->target.name();
        auto target = call->target;
        return locals()->find_function(functionName);
    }

    void LLVMCodeGenerator::codegenFunction(Ref<UserFunction> function, const FunctionDef* funcDef) {
        PEP_TRACE(TraceChannel::Codegen, llvm::formatv("Generate {0}...", funcDef->signature()));
        Messages::indent(TraceChannel::Codegen);
        module->get_debug_info()->setSourceLocation(funcDef->source_loc);
        push_function(function);

        // track any references that only exist in this scope, they will need cleanup at the end
        Vector<Address> localRefs;

        // Allocate parameters
        auto llvmFunction = function->function();
        for (int param_idx = 0; param_idx < function->params().size(); ++param_idx) {
            auto param = function->params()[param_idx];
            auto type = param.type;
            auto arg = Address(param.type, llvmFunction->getArg(param_idx));
            auto addr = ir()->CreateAlloca(*type, nullptr, param.name);
            auto local = Address(type, addr, param.name);

            module->get_debug_info()->emitParameter(param_idx, local);

            const bool isThis = param_idx == 0 && param.name == "this";

            // methods should never alter the refcount of `this`, and special methods do not alter ref counts
            // at all (they don't have arguments anyway)
            if (!isThis && function->count_arg_refs()) {
                type->ops()->init(local, arg);
                if (local.type->is<RefType>())
                    localRefs.emplace_back(local);
            } else {
                ir()->CreateStore(arg, local);
            }

            locals()->symbol(local);
        }

        codegenBlock(function, funcDef->body, function->body, function->return_expr, localRefs);

        Messages::outdent(TraceChannel::Codegen);
        pop_scope();
    }

    void LLVMCodeGenerator::instantiate(const sema::FunctionNode* fn) {
        // generic functions don't get instantiated, they're abstract
        if (fn->is_generic())
            return;

        Messages::indent(TraceChannel::Codegen);
        PEP_TRACE(TraceChannel::Codegen, "Instantiating {0}", fn->name);

        auto return_type = Types::get(fn->return_type.to_string());
        if (!return_type)
            throw CompileError(
                fn->source_loc, "Unknown return type in {0}: {1}", fn->type.to_string(), fn->return_type.to_string());
        auto params = Query(fn->parameters).select<pepper::Param>([&](const auto& p) {
            auto type = Types::get(p.type.to_string());
            if (!type)
                throw CompileError(fn->source_loc, "Unknown type for parameter {0}: {1}", p.name, p.type.to_string());
            return pepper::Param{p.name, type, p.default_value ? codegen(p.default_value) : Address::null()};
        });
        auto function = [&]() -> Ref<Function> {
            if (auto extFunction = fn->as<ExternFunctionRef>()) {
                return Ref<Function>::create(module->get_llvm_module(),
                                          fn->name,
                                          return_type,
                                          params,
                                          extFunction->is_vararg,
                                          extFunction->is_weak ? Function::LinkageType::ExternalWeakLinkage
                                                               : Function::LinkageType::ExternalLinkage);
            }
            return Ref<UserFunction>::create(module->get_llvm_module(), fn->name, return_type, params);
        }();
        locals()->function(function);
        Messages::outdent(TraceChannel::Codegen);
    }

    Address LLVMCodeGenerator::emit(const FunctionDef* functionDef) {
        // generic functions don't get generated, they're abstract
        if (functionDef->is_generic())
            return Address::null();

        const auto& function_name = functionDef->name;
        const auto function = locals()->find_function(functionDef->name);
        if (!function) {
            throw CompileError(functionDef->source_loc, "Function {0} not found", function_name);
        }
        codegenFunction(function, functionDef);
        return Address{function->type(), function->function(), function->name()};
    }

    Address LLVMCodeGenerator::emit(const ExternFunctionRef* functionDecl) {
        auto function = locals()->find_function(functionDecl->name);
        return Address{function->type(), function->function(), function->name()};
    }

    Address LLVMCodeGenerator::emit(const Return* ret) {
        auto function = locals()->function_target().as<UserFunction>();
        if (ret->expr) {
            auto returnValueExpr = codegen(ret->expr);
            auto returnValue = load(returnValueExpr);
            auto return_type = function->return_type();
            if (!return_type)
                throw CompileError(ret->source_loc, "Unknown return type {0}", ret->type().to_string());
            auto type = return_type->ops();
            auto rv = type->coerce(returnValue);
            // save the return value to the return value address
            ir()->CreateStore(rv, function->return_value);
        }
        // jump to the return block
        return Address{Types::Void, ir()->CreateBr(function->return_expr)};
    }

    Address LLVMCodeGenerator::emit(const FunctionCall* call) {
        auto function = resolveFunction(call);
        if (!function) {
            throw CompileError(call->source_loc, "Function {0} not found", call->target.name());
        }
        Vector<Address> args;
        const auto& callArgs = call->args;
        for (const auto& argExpr : callArgs) {
            auto arg = codegen(argExpr);
            arg = load(arg);
            args.push_back(arg);
        }
        return Address{function->return_type(), function->call(args)};
    }
} // namespace pepper
