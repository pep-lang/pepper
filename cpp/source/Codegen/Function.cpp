
#include "Codegen/Function.h"

#include "Codegen/Context.h"
#include "Codegen/Scope.h"
#include "Codegen/Types.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/IRBuilder.h"

namespace pepper {
    Function::Function(const Name& name, Ref<Type> returnType, const Params& params)
        : Identifier(name)
        , ReturnType(returnType)
        , Parameters(params) {
        std::vector<llvm::Type*> paramTypes;
        std::for_each(params.begin(), params.end(), [&](auto p) { paramTypes.push_back(*p.ParamType); });
        FuncType = llvm::FunctionType::get(*returnType, paramTypes, false);
        Func =
            llvm::Function::Create(FuncType, llvm::GlobalValue::ExternalLinkage, Identifier, Context::get().module());
    }

    UserFunction::UserFunction(const Name& name, Ref<Type> returnType, const Params& params)
        : Function(name, returnType, params) {
        auto& context = Context::get().module()->getContext();
        Body = llvm::BasicBlock::Create(context, "entry");
        Builder = Ref<llvm::IRBuilder<>>::New(Body);
    }
} // namespace pepper
