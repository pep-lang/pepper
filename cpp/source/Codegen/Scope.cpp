//
// Created by Justin Boswell on 12/21/22.
//

#include "Codegen/Scope.h"

#include "Function.h"
#include "llvm/ADT/STLExtras.h"

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

    llvm::IRBuilderBase* Scope::builder() const {
        return Builder ? Builder.get() : (Outer ? Outer->builder() : nullptr);
    }

    llvm::IRBuilderBase* Scope::registers() const {
        auto func = returnTarget().as<UserFunction>();
        var funcStart = func.Body.FirstInstruction;
        var builder = func.Builder;
        if (funcStart.Handle != 0) {
            // skip past existing locals
            for (int localIdx = 0; localIdx < func.NumLocals; ++localIdx)
                funcStart = funcStart.NextInstruction;
            builder = Context.Module.Context.CreateBuilder();
            builder.PositionBefore(funcStart);
        }
        ++func.NumLocals;
        return builder;
    }
}
