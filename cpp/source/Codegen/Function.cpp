
#include "Codegen/Function.h"

#include "Codegen/Scope.h"
#include "Compiler/Context.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/IRBuilder.h"

namespace pepper {
    Function::Function(std::string name, llvm::Type* returnType, const Params& params)
        : Name(std::move(name))
        , ReturnType(returnType)
        , Parameters(params) {
        Context::get().locals()->Functions[name] = ref();
        std::vector<llvm::Type*> paramTypes;
        std::for_each(params.begin(), params.end(), [&](auto p) { paramTypes.push_back(p.Type); });
        FuncType = llvm::FunctionType::get(returnType, paramTypes, false);
        Func = llvm::Function::Create(FuncType, llvm::GlobalValue::ExternalLinkage, Name, Context::get().module());
    }

    UserFunction::UserFunction(std::string name, llvm::Type* returnType, const Params& params)
        : Function(name, returnType, params) {
        Context::get().locals()->Functions[name] = ref();
        auto& context = Context::get().module()->getContext();
        Body = llvm::BasicBlock::Create(context, "entry");
        Builder = Ref<llvm::IRBuilder<>>::create(Body);
    }
} // namespace pepper
