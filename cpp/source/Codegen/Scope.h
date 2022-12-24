//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <string>
#include <utility>
#include <vector>

#include "Core/Common.h"
#include "llvm/ADT/StringMap.h"

namespace llvm {
    class Function;
    class IRBuilderBase;
    class Type;
    class Value;
} // namespace llvm

namespace pepper {
    class Function;
    class Symbol;
    class Type;

    struct Scope {
        std::string Name;
        Ref<Scope> Outer;

        llvm::StringMap<llvm::Type*> Types;

        llvm::StringMap<llvm::Value*> Symbols;
        std::vector<std::string> OrderedSymbols;

        llvm::StringMap<Ref<Function>> Functions;
        Ref<Function> FunctionTarget;

        std::vector<llvm::Value*> Stack;

        Ref<llvm::IRBuilderBase> Builder;

        explicit Scope(const std::string& name = "Anonymous", Ref<Scope> outer = nullptr)
            : Name(name)
            , Outer(std::move(outer)) {
        }

        void pushStack(llvm::Value* value) {
            Stack.push_back(value);
        }

        llvm::Value* popStack() {
            auto top = Stack.back();
            Stack.pop_back();
            return top;
        }

        llvm::Value* peekStack(unsigned int idx) {
            return Stack[Stack.size() - 1 - idx];
        }

        void newSymbol(const std::string& identifier, llvm::Value* value);
        void newFunction(Ref<Function> function, const std::string& name = "");

        [[nodiscard]] Ref<Function> findFunction(const std::string& name) const;
        [[nodiscard]] llvm::Value* findSymbol(const std::string& identifier) const;
        Ref<llvm::IRBuilderBase> builder() const;
        Ref<llvm::IRBuilderBase> registers() const;
        Ref<Function> functionTarget() const;
    };
} // namespace pepper
