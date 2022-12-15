
#pragma once

#include "Compiler/Function.h"
#include "Compiler/Type.h"
#include "Compiler/Value.h"
#include "llvm/ADT/StringMap.h"
#include <memory>
#include <stack>
#include <string>

namespace llvm {
    class IRBuilderBase;
}

namespace pepper {
    class Type;
    class Value;
    class Function;
    class UserFunction;

    class Scope {
        struct StackEntry {};

      public:
        Scope(Scope* outer = nullptr)
            : Outer(outer) {
        }

        Scope* Outer = nullptr;
        std::shared_ptr<llvm::IRBuilderBase> Builder = nullptr;
        llvm::StringMap<Ref<Type>> Types;
        llvm::StringMap<Ref<Function>> Functions;
        llvm::StringMap<Ref<Value>> Locals;
        std::stack<StackEntry> Stack;
        std::shared_ptr<UserFunction> ReturnTarget = nullptr;

        std::shared_ptr<llvm::IRBuilderBase> ir() const {
            return (Builder) ? Builder : Outer->Builder;
        }

        std::shared_ptr<llvm::IRBuilderBase> localRegisters() const;
    };
} // namespace pepper
