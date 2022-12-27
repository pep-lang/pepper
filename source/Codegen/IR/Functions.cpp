//
// Created by Justin Boswell on 12/26/22.
//

#include "AST/Functions.h"

#include "Codegen/Context.h"
#include "Codegen/Function.h"
#include "Codegen/IR/Codegen.h"
#include "Codegen/TypeOps.h"
#include "Codegen/Types.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"

namespace pepper {
    using namespace pepper::ast;

    void Codegen::codegenFunction(Ref<UserFunction> function, Ref<FunctionDef> funcDef) {
        Context::get().pushFunction(function);

        // Allocate parameters
        auto llvmFunction = function->function();
        auto args = Vector<llvm::Value*>();
        for (int paramIdx = 0; paramIdx < function->params().size(); ++paramIdx) {
            auto param = function->params()[paramIdx];
            auto arg = llvmFunction->getArg(paramIdx);
            auto local = ir()->CreateAlloca(*param.ParamType, nullptr, param.ParamName);
            ir()->CreateStore(arg, local);
            Context::get().locals()->newSymbol(param.ParamName, local);
            args.push_back(local);
        }

        // Push all known variables (except params, which are already done above) at the top of the function block
        Query(funcDef->locals())
            .without([](auto local) { return local->template is<ParamDef>(); })
            .each([&](auto local) { codegen(local); });

        // Emit the body of the function, after ensuring there is a return instruction
        auto lastExpr = (funcDef->body().size()) ? funcDef->body().back() : nullptr;
        if (!lastExpr || !lastExpr->is<Return>()) {
            funcDef->body().push_back(Ref<Return>::New(funcDef));
        }
        std::for_each(funcDef->body().begin(), funcDef->body().end(), [&](auto expr) { codegen(expr); });

        Context::get().popScope();
        Context::get().locals()->newFunction(function);
    }

    llvm::Value* Codegen::emit(Ref<FunctionDef> functionDef) {
        auto returnType = Types::get(functionDef->returnType());
        auto params = Query(functionDef->params()).select<pepper::Param>([this](auto p) {
            return pepper::Param{p.Identifier, Types::get(p.Type), p.Default ? codegen(p.Default) : nullptr};
        });
        auto function = Ref<UserFunction>::New(functionDef->identifier(), returnType, params);
        codegenFunction(function, functionDef);
        return function->function();
    }

    llvm::Value* Codegen::emit(Ref<Return> ret) {
        if (ret->value()) {
            auto returnValueExpr = codegen(ret->value());
            auto returnValue = read(returnValueExpr);
            auto func = ret->target();
            auto returnType = Types::get(func->returnType());
            auto type = TypeOps::get(*returnType);
            auto rv = type->coerce(returnValue);
            return ir()->CreateRet(rv);
        }
        return ir()->CreateRetVoid();
    }

    llvm::Value* Codegen::emit(Ref<FunctionCall> call) {
        auto function = resolveFunction(call);
        if (!function) {
            throw CompileError("Function {0} not found", call->target()->identifier());
        }
        Vector<llvm::Value*> args;
        if (function->is<Method>()) {
            auto thisRef = Context::get().locals()->findSymbol("this");
            assert(thisRef);
            thisRef = read(thisRef);
            args.push_back(thisRef);
        }

        const auto& callArgs = call->args();
        for (auto argExpr : callArgs) {
            args.push_back(codegen(argExpr));
        }
        return function->call(args);
    }
} // namespace pepper
