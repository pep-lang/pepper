

#pragma once

#include <string>
#include <utility>

#include "CodeGen/Address.h"
#include "Core/Common.h"
#include "Core/Vector.h"
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
    class Type;

    struct Scope {
        std::string Name;
        Ref<Scope> Outer;

        llvm::StringMap<llvm::Type*> Types;

        llvm::StringMap<Address> Symbols;
        Vector<std::string> OrderedSymbols;

        llvm::StringMap<Ref<Struct>> Structs;

        llvm::StringMap<Ref<Function>> Functions;
        Ref<UserFunction> FunctionTarget;

        Ref<Struct> This;

        Ref<llvm::IRBuilderBase> Builder;

        explicit Scope(const std::string& name = "Anonymous", Ref<Scope> outer = nullptr)
            : Name(name)
            , Outer(std::move(outer)) {}

        void newSymbol(const Address& value);
        void newFunction(Ref<Function> function, const std::string& name = "");

        [[nodiscard]] Ref<Function> findFunction(const std::string& name) const;
        [[nodiscard]] const Address& findSymbol(const std::string& identifier, bool localOnly = false) const;
        Ref<llvm::IRBuilderBase> builder() const;
        Ref<UserFunction> functionTarget() const;
    };
} // namespace pepper
