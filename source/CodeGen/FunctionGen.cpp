//
// Created by Justin Boswell on 12/26/22.
//

#include "AST/Functions.h"
#include "CodeGen/Codegen.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Core/Query.h"
#include "Frontend/Function.h"
#include "Frontend/LLVMUtils.h"
#include "Frontend/TypeOps.h"
#include "Frontend/Types.h"

namespace pepper {
    using namespace pepper::ast;

    Ref<Function> Codegen::resolveFunction(Ref<FunctionCall> call) {
        auto functionName = call->Target->Name;
        auto target = call->Target;
        return locals()->findFunction(functionName);
    }

    void Codegen::codegenFunction(Ref<UserFunction> function, Ref<FunctionDef> funcDef) {
        PEP_TRACE(TraceChannel::Codegen, llvm::formatv("Generate {0}...", funcDef->Name));
        pushFunction(function);

        // Allocate parameters
        auto llvmFunction = function->function();
        for (int paramIdx = 0; paramIdx < function->params().size(); ++paramIdx) {
            auto param = function->params()[paramIdx];
            auto type = param.Type;
            auto arg = Value(param.Type, llvmFunction->getArg(paramIdx));
            auto addr = ir()->CreateAlloca(*type, nullptr, param.Name);
            auto local = Value(type, addr, param.Name);
            // Special methods use raw stores to avoid ref-counting getting in the way
            if (function->countArgRefs()) {
                type->ops()->init(local, arg);
            } else {
                ir()->CreateStore(arg, local);
            }

            locals()->newSymbol(local);
        }

        codegenBlock(function, funcDef->Body, function->Body, function->Return);

        popScope();
        locals()->newFunction(function);
    }

    Value Codegen::emit(Ref<FunctionDef> functionDef) {
        auto returnType = Types::get(functionDef->ReturnType.toString());
        auto params = Query(functionDef->Parameters).select<pepper::Param>([this](auto p) {
            return pepper::Param{p.Name, Types::get(p.Type.toString()), p.Default ? codegen(p.Default) : Value::Null()};
        });
        auto function = Ref<UserFunction>::New(functionDef->Name, returnType, params);
        codegenFunction(function, functionDef);
        return Value{function->type(), function->function()};
    }

    Value Codegen::emit(Ref<Return> ret) {
        auto function = locals()->functionTarget().as<UserFunction>();
        if (ret->Value) {
            auto returnValueExpr = codegen(ret->Value);
            auto returnValue = load(returnValueExpr);
            auto returnType = Types::get(ret->Type.toString());
            auto type = returnType->ops();
            auto rv = type->coerce(returnValue);
            // save the return value to the return value address
            ir()->CreateStore(rv, function->ReturnValue);
        }
        // jump to the return block
        return Value{Types::Void, ir()->CreateBr(function->Return)};
    }

    Value Codegen::emit(Ref<FunctionCall> call) {
        auto function = resolveFunction(call);
        if (!function) {
            throw CompileError(call->Source, "Function {0} not found", call->Target->Name);
        }
        Vector<Value> args;
        const auto& callArgs = call->Args;
        for (const auto& argExpr : callArgs) {
            auto arg = codegen(argExpr);
            arg = load(arg);
            args.push_back(arg);
        }
        return Value{function->returnType(), function->call(args)};
    }
} // namespace pepper
