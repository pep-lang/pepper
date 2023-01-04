//
// Created by Justin Boswell on 12/21/22.
//

#include "Codegen/Scope.h"

#include "Codegen/Function.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/IR/IRBuilder.h"

namespace pepper {
    void Scope::newFunction(Ref<Function> function, const std::string& name) {
        auto functionName = name.empty() ? function->name() : name;
        Functions[functionName] = function;
    }

    Ref<Function> Scope::findFunction(const std::string& name) const {
        auto it = Functions.find(name);
        if (it != Functions.end()) {
            return it->second;
        }
        return Outer ? Outer->findFunction(name) : nullptr;
    }

    void Scope::newSymbol(const Value& value) {
        Symbols[value.Identifier] = value;
    }

    const Value& Scope::findSymbol(const std::string& identifier) const {
        auto it = Symbols.find(identifier);
        if (it != Symbols.end())
            return it->second;
        return Outer ? Outer->findSymbol(identifier) : Value::Null();
    }

    Ref<Function> Scope::functionTarget() const {
        return FunctionTarget ? FunctionTarget : (Outer ? Outer->functionTarget() : nullptr);
    }

    Ref<llvm::IRBuilderBase> Scope::builder() const {
        return Builder ? Builder : (Outer ? Outer->builder() : nullptr);
    }

    //    Ref<llvm::IRBuilderBase> Scope::registers() const {
    //        auto func = functionTarget().as<UserFunction>();
    //        auto funcStart = func->Body->getFirstInsertionPt();
    //        auto builder = func->Builder;
    //        if (funcStart != func->Body->getInstList().begin()) {
    //            // skip past existing locals
    //            for (int localIdx = 0; localIdx < func->NumLocals; ++localIdx)
    //                ++funcStart;
    //            builder = Ref<llvm::IRBuilder<>>::New(func->Body);
    //            builder->SetInsertPoint(func->Body, funcStart);
    //        }
    //        ++func->NumLocals;
    //        return builder;
    //    }
} // namespace pepper
