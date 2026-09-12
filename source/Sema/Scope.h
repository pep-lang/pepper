

#pragma once

#include <string>
#include <utility>

#include "CodeGen/LLVM/Address.h"
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

    struct Scope {
        std::string name;
        Ref<Scope> outer;

        llvm::StringMap<llvm::Type*> types;

        llvm::StringMap<Address> symbols;
        Vector<std::string> ordered_symbols;

        llvm::StringMap<Ref<Struct>> structs;

        llvm::StringMap<Ref<Function>> functions;
        Ref<UserFunction> func_target;

        Ref<Struct> this_struct;

        Ref<llvm::IRBuilderBase> ir_builder;

        explicit Scope(const std::string& name = "Anonymous", Ref<Scope> outer = nullptr)
            : name(name)
            , outer(std::move(outer)) {}

        void symbol(const Address& value);
        void function(Ref<Function> function, const std::string& name = "");

        [[nodiscard]] Ref<Function> find_function(const std::string& name) const;
        [[nodiscard]] const Address& find_symbol(const std::string& identifier, bool localOnly = false) const;
        Ref<llvm::IRBuilderBase> builder() const;
        Ref<UserFunction> function_target() const;
    };
} // namespace pepper
