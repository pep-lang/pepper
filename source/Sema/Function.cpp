
#include "Function.h"

#include "Core/Exceptions.h"
#include "Operations.h"
#include "SemaContext.h"
#include "Struct.h"
#include "Types.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/IRBuilder.h"

namespace pepper {
    Function::Function(llvm::Module& module,
                       const Ident& name,
                       Ref<Type> returnType,
                       const Params& params,
                       bool vararg,
                       LinkageType linkage)
        : Name(name)
        , ReturnType(returnType)
        , Parameters(params)
        , Vararg(vararg)
        , Linkage(linkage) {
        Vector<llvm::Type*> paramTypes;
        std::for_each(params.begin(), params.end(), [&](auto p) { paramTypes.push_back(*p.Type); });
        auto llvmType = llvm::FunctionType::get(*returnType, paramTypes, false);
        auto sig = Types::toString(llvmType);
        FuncType = Types::add(Ref<Type>::New(sig, llvmType));
        Func = llvm::Function::Create(llvmType, Linkage, Name, module);
    }

    Address Function::call(const Vector<Address>& args) const {
        // fill in supplied params
        Vector<llvm::Value*> coercedArgs;
        int idx = 0;
        for (const auto& arg : args) {
            auto expectedType = Parameters[idx++].Type->ops();
            coercedArgs.push_back(expectedType->coerce(arg));
        }

        // fill in default params
        for (auto argIdx = coercedArgs.size(); argIdx < Parameters.size(); ++argIdx) {
            const auto& param = Parameters[argIdx];
            if (!param.Default) {
                throw CompileError("Missing argument {0}({1}) of type {2} to {3}",
                                   argIdx,
                                   param.Name,
                                   Types::toString(param.Type),
                                   Name);
            }
            coercedArgs.push_back(param.Type->ops()->coerce(param.Default));
        }
        auto functionType = llvm::cast<llvm::FunctionType>(Types::get(FuncType.get()));
        return Address{ReturnType, SemaContext::get().ir()->CreateCall(functionType, Func, coercedArgs)};
    }

    UserFunction::UserFunction(llvm::Module& module, const Ident& name, Ref<Type> returnType, const Params& params)
        : Function(module, name, returnType, params) {
        Body = llvm::BasicBlock::Create(module.getContext(), "entry", Func);
        Builder = Ref<llvm::IRBuilder<>>::New(Body);

        // Set up return block and return instruction
        Return = llvm::BasicBlock::Create(module.getContext(), "return", Func);
        auto builder = Ref<llvm::IRBuilder<>>::New(Return);
        builder->SetInsertPoint(Return);
        if (returnType != Types::Void) {
            ReturnValue = Address{returnType, Builder->CreateAlloca(*returnType, nullptr, "retval")};
            builder->CreateRet(builder->CreateLoad(*ReturnType, ReturnValue));
        } else {
            builder->CreateRetVoid();
        }
    }

    llvm::BasicBlock* UserFunction::appendBlock(const Ident& name) {
        auto block = llvm::BasicBlock::Create(Func->getContext(), name, Func, Return);
        return block;
    }

    bool UserFunction::countArgRefs() const {
        return true;
    }

    bool Method::countArgRefs() const {
        if (!UserFunction::countArgRefs())
            return false;

        if (Name.find(".__") != std::string::npos)
            return false;

        return true;
    }
} // namespace pepper
