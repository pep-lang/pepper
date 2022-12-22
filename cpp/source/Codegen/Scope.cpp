//
// Created by Justin Boswell on 12/21/22.
//

#include "Codegen/Scope.h"

#include "Function.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/IRBuilder.h"

namespace pepper {
    Ref<Function> Scope::findFunction(const std::string& name) const {
        auto it = Functions.find(name);
        if (it != Functions.end()) {
            return it->second;
        }
        return Outer ? Outer->findFunction(name) : nullptr;
    }

    llvm::Value* Scope::findSymbol(const std::string& name) const {
        auto it = Symbols.find(name);
        if (it != Symbols.end())
            return it->second;
        return Outer ? Outer->findSymbol(name) : nullptr;
    }

    Ref<Function> Scope::returnTarget() const {
        return ReturnTarget ? ReturnTarget : (Outer ? Outer->returnTarget() : nullptr);
    }

    Ref<llvm::IRBuilderBase> Scope::builder() const {
        return Builder ? Builder : (Outer ? Outer->builder() : nullptr);
    }

    Ref<llvm::IRBuilderBase> Scope::registers() const {
        auto func = returnTarget().as<UserFunction>();
        auto funcStart = func->Body->getFirstInsertionPt();
        auto builder = func->Builder;
        if (funcStart != func->Body->getInstList().begin()) {
            // skip past existing locals
            for (int localIdx = 0; localIdx < func->NumLocals; ++localIdx)
                ++funcStart;
            builder = Ref<llvm::IRBuilder<>>::create(func->Body);
            builder->SetInsertPoint(func->Body, funcStart);
        }
        ++func->NumLocals;
        return builder;
    }
} // namespace pepper
