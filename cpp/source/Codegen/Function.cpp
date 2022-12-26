
#include "Codegen/Function.h"

#include "Codegen/Context.h"
#include "Codegen/Scope.h"
#include "Codegen/TypeOps.h"
#include "Codegen/Types.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/IRBuilder.h"

namespace pepper {
    Function::Function(const Name& name, Ref<Type> returnType, const Params& params)
        : Identifier(name)
        , ReturnType(returnType)
        , Parameters(params) {
        Vector<llvm::Type*> paramTypes;
        std::for_each(params.begin(), params.end(), [&](auto p) { paramTypes.push_back(*p.ParamType); });
        FuncType = llvm::FunctionType::get(*returnType, paramTypes, false);
        Func =
            llvm::Function::Create(FuncType, llvm::GlobalValue::ExternalLinkage, Identifier, Context::get().module());
    }

    llvm::Value* Function::call(const Vector<llvm::Value*>& args) const {
        // TODO: deal with default values for params
        Vector<llvm::Value*> coercedArgs;
        int idx = 0;
        for (auto* arg : args) {
            auto expectedType = TypeOps::get(*Parameters[idx++].ParamType);
            coercedArgs.push_back(expectedType->coerce(arg));
        }
        return Context::get().locals()->Builder->CreateCall(FuncType, Func, coercedArgs);
    }

    UserFunction::UserFunction(const Name& name, Ref<Type> returnType, const Params& params)
        : Function(name, returnType, params) {
        auto& context = Context::get().module()->getContext();
        Body = llvm::BasicBlock::Create(context, "entry", Func);
        Builder = Ref<llvm::IRBuilder<>>::New(Body);
    }

    Ref<ExternFunction> ExternFunction::Malloc;
    Ref<ExternFunction> ExternFunction::Free;

    void ExternFunction::StaticInit() {
        Malloc = Ref<ExternFunction>::New("malloc", Types::VoidPtr, Params{{"size", Types::UInt64}});
        Free = Ref<ExternFunction>::New("free", Types::Void, Params{{"ptr", Types::VoidPtr}});
    }
} // namespace pepper
