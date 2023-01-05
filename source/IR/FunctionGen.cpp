//
// Created by Justin Boswell on 12/26/22.
//

#include "AST/Functions.h"
#include "Codegen.h"
#include "Codegen/Context.h"
#include "Codegen/Function.h"
#include "Codegen/TypeOps.h"
#include "Codegen/Types.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"

namespace pepper {
    using namespace pepper::ast;

    Ref<Function> Codegen::resolveFunction(Ref<FunctionCall> call) {
        auto functionName = call->Target->Name;
        auto target = call->Target;
        return locals()->findFunction(functionName);
    }

    void Codegen::codegenFunction(Ref<UserFunction> function, Ref<FunctionDef> funcDef) {
        pushFunction(function);

        // Allocate parameters
        auto llvmFunction = function->function();
        for (int paramIdx = 0; paramIdx < function->params().size(); ++paramIdx) {
            auto param = function->params()[paramIdx];
            auto arg = llvmFunction->getArg(paramIdx);
            auto addr = ir()->CreateAlloca(*param.ParamType, nullptr, param.ParamName);
            auto local = Value(param.ParamType, addr, param.ParamName);
            ir()->CreateStore(arg, local);
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
            auto returnValue = read(returnValueExpr);
            auto returnType = Types::get(ret->Type.toString());
            auto type = TypeOps::get(returnType);
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
        if (function->is<Method>()) {
            auto thisRef = locals()->findSymbol("this");
            assert(thisRef);
            thisRef = read(thisRef);
            args.push_back(thisRef);
        }

        const auto& callArgs = call->Args;
        for (const auto& argExpr : callArgs) {
            args.push_back(codegen(argExpr));
        }
        return Value{function->returnType(), function->call(args)};
    }
} // namespace pepper
