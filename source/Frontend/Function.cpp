
#include "Frontend/Function.h"

#include "Core/Exceptions.h"
#include "Frontend/Context.h"
#include "Frontend/TypeOps.h"
#include "Frontend/Types.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/IRBuilder.h"

namespace pepper {
    Function::Function(const Ident& name, Ref<TypeInfo> returnType, const Params& params)
        : Identifier(name)
        , ReturnType(returnType)
        , Parameters(params) {
        Vector<llvm::Type*> paramTypes;
        std::for_each(params.begin(), params.end(), [&](auto p) { paramTypes.push_back(*p.ParamType); });
        auto llvmType = llvm::FunctionType::get(*returnType, paramTypes, false);
        auto sig = Types::toString(llvmType);
        FuncType = Types::add(Ref<TypeInfo>::New(sig, llvmType));
        Func =
            llvm::Function::Create(llvmType, llvm::GlobalValue::ExternalLinkage, Identifier, Context::get().module());
    }

    Value Function::call(const Vector<Value>& args) const {
        // fill in supplied params
        Vector<llvm::Value*> coercedArgs;
        int idx = 0;
        for (const auto& arg : args) {
            auto expectedType = Parameters[idx++].ParamType->ops();
            coercedArgs.push_back(expectedType->coerce(arg));
        }

        // fill in default params
        for (auto argIdx = coercedArgs.size(); argIdx < Parameters.size(); ++argIdx) {
            const auto& param = Parameters[argIdx];
            if (!param.Default) {
                throw CompileError("Missing argument {0}({1}) of type {2} to {3}",
                                   argIdx,
                                   param.ParamName,
                                   Types::toString(param.ParamType),
                                   Identifier);
            }
            coercedArgs.push_back(param.ParamType->ops()->coerce(param.Default));
        }
        return Value{ReturnType,
                     Context::get().ir()->CreateCall((llvm::FunctionType*)FuncType->llvmType(), Func, coercedArgs)};
    }

    UserFunction::UserFunction(const Ident& name, Ref<TypeInfo> returnType, const Params& params)
        : Function(name, returnType, params) {
        auto& context = Context::get().module()->getContext();
        Body = llvm::BasicBlock::Create(context, "entry", Func);
        Builder = Ref<llvm::IRBuilder<>>::New(Body);

        // Set up return block and return instruction
        Return = llvm::BasicBlock::Create(context, "return", Func);
        auto builder = Ref<llvm::IRBuilder<>>::New(Return);
        builder->SetInsertPoint(Return);
        if (returnType != Types::Void) {
            ReturnValue = Value{returnType, Builder->CreateAlloca(*returnType, nullptr, "retval")};
            builder->CreateRet(builder->CreateLoad(*ReturnType, ReturnValue));
        } else {
            builder->CreateRetVoid();
        }
    }

    llvm::BasicBlock* UserFunction::appendBlock(const Ident& name) {
        auto block = llvm::BasicBlock::Create(Func->getContext(), name, Func, Return);
        return block;
    }
} // namespace pepper
