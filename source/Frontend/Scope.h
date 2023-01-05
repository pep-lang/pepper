//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <string>
#include <utility>

#include "Core/Common.h"
#include "Core/Vector.h"
#include "IR/Value.h"
#include "llvm/ADT/StringMap.h"

namespace llvm {
    class Function;
    class IRBuilderBase;
    class Type;
} // namespace llvm

namespace pepper {
    class Function;
    class UserFunction;
    class Struct;
    class Symbol;
    class TypeInfo;

    struct Scope {
        std::string Name;
        Ref<Scope> Outer;

        llvm::StringMap<llvm::Type*> Types;

        llvm::StringMap<Value> Symbols;
        Vector<std::string> OrderedSymbols;

        llvm::StringMap<Ref<Struct>> Structs;

        llvm::StringMap<Ref<Function>> Functions;
        Ref<UserFunction> FunctionTarget;

        Ref<Struct> This;

        Ref<llvm::IRBuilderBase> Builder;

        explicit Scope(const std::string& name = "Anonymous", Ref<Scope> outer = nullptr)
            : Name(name)
            , Outer(std::move(outer)) {
        }

        void newSymbol(const Value& value);
        void newFunction(Ref<Function> function, const std::string& name = "");

        [[nodiscard]] Ref<Function> findFunction(const std::string& name) const;
        [[nodiscard]] const Value& findSymbol(const std::string& identifier) const;
        Ref<llvm::IRBuilderBase> builder() const;
        Ref<UserFunction> functionTarget() const;
    };
} // namespace pepper
