

#include "AST/Functions.h"
#include "CodeGen/CodeGenerator.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "Frontend/Function.h"
#include "Frontend/LLVMUtils.h"
#include "Frontend/Operations.h"
#include "Frontend/Types.h"

namespace pepper {
    using namespace pepper::ast;

    Ref<Function> CodeGenerator::resolveFunction(const FunctionCall* call) {
        auto functionName = call->Target.name();
        auto target = call->Target;
        return locals()->findFunction(functionName);
    }

    void CodeGenerator::codegenFunction(Ref<UserFunction> function, const FunctionDef* funcDef) {
        PEP_TRACE(TraceChannel::Codegen, llvm::formatv("Generate {0}...", funcDef->signature()));
        Messages::Indent(TraceChannel::Codegen);
        Module->getDebugInfo()->setSourceLocation(funcDef->Source);
        pushFunction(function);

        // track any references that only exist in this scope, they will need cleanup at the end
        Vector<Address> localRefs;

        // Allocate parameters
        auto llvmFunction = function->function();
        for (int paramIdx = 0; paramIdx < function->params().size(); ++paramIdx) {
            auto param = function->params()[paramIdx];
            auto type = param.Type;
            auto arg = Address(param.Type, llvmFunction->getArg(paramIdx));
            auto addr = ir()->CreateAlloca(*type, nullptr, param.Name);
            auto local = Address(type, addr, param.Name);

            Module->getDebugInfo()->emitParameter(paramIdx, local);

            const bool isThis = paramIdx == 0 && param.Name == "this";

            // Methods should never alter the refcount of `this`, and special methods do not alter ref counts
            // at all (they don't have arguments anyway)
            if (!isThis && function->countArgRefs()) {
                type->ops()->init(local, arg);
                if (local.Ty->is<RefType>())
                    localRefs.emplace_back(local);
            } else {
                ir()->CreateStore(arg, local);
            }

            locals()->newSymbol(local);
        }

        codegenBlock(function, funcDef->Body, function->Body, function->Return, localRefs);

        Messages::Outdent(TraceChannel::Codegen);
        popScope();
    }

    void CodeGenerator::instantiate(const ast::FunctionNode* fn) {
        // generic functions don't get instantiated, they're abstract
        if (fn->isGeneric())
            return;

        Messages::Indent(TraceChannel::Codegen);
        PEP_TRACE(TraceChannel::Codegen, "Instantiating {0}", fn->Name);

        auto returnType = Types::get(fn->ReturnType.toString());
        if (!returnType)
            throw CompileError(
                fn->Source, "Unknown return type in {0}: {1}", fn->Type.toString(), fn->ReturnType.toString());
        auto params = Query(fn->Parameters).select<pepper::Param>([&](const auto& p) {
            auto type = Types::get(p.Type.toString());
            if (!type)
                throw CompileError(fn->Source, "Unknown type for parameter {0}: {1}", p.Name, p.Type.toString());
            return pepper::Param{p.Name, type, p.Default ? codegen(p.Default) : Address::Null()};
        });
        auto function = [&]() -> Ref<Function> {
            if (auto extFunction = fn->as<ExternFunctionRef>()) {
                return Ref<Function>::New(Module->getModule(),
                                          fn->Name,
                                          returnType,
                                          params,
                                          extFunction->Vararg,
                                          extFunction->Weak ? Function::LinkageType::ExternalWeakLinkage
                                                            : Function::LinkageType::ExternalLinkage);
            }
            return Ref<UserFunction>::New(Module->getModule(), fn->Name, returnType, params);
        }();
        locals()->newFunction(function);
        Messages::Outdent(TraceChannel::Codegen);
    }

    Address CodeGenerator::emit(const FunctionDef* functionDef) {
        // generic functions don't get generated, they're abstract
        if (functionDef->isGeneric())
            return Address::Null();

        auto function = locals()->findFunction(functionDef->Name);
        codegenFunction(function, functionDef);
        return Address{function->type(), function->function(), function->name()};
    }

    Address CodeGenerator::emit(const ExternFunctionRef* functionDecl) {
        auto function = locals()->findFunction(functionDecl->Name);
        return Address{function->type(), function->function(), function->name()};
    }

    Address CodeGenerator::emit(const Return* ret) {
        auto function = locals()->functionTarget().as<UserFunction>();
        if (ret->Value) {
            auto returnValueExpr = codegen(ret->Value);
            auto returnValue = load(returnValueExpr);
            auto returnType = Types::get(ret->Type.toString());
            if (!returnType)
                throw CompileError(ret->Source, "Unknown return type {0}", ret->Type.toString());
            auto type = returnType->ops();
            auto rv = type->coerce(returnValue);
            // save the return value to the return value address
            ir()->CreateStore(rv, function->ReturnValue);
        }
        // jump to the return block
        return Address{Types::Void, ir()->CreateBr(function->Return)};
    }

    Address CodeGenerator::emit(const FunctionCall* call) {
        auto function = resolveFunction(call);
        if (!function) {
            throw CompileError(call->Source, "Function {0} not found", call->Target.name());
        }
        Vector<Address> args;
        const auto& callArgs = call->Args;
        for (const auto& argExpr : callArgs) {
            auto arg = codegen(argExpr);
            arg = load(arg);
            args.push_back(arg);
        }
        return Address{function->returnType(), function->call(args)};
    }
} // namespace pepper
