//
// Created by Justin Boswell on 1/1/23.
//

#pragma once

#include <variant>

#include "Core/Common.h"
#include "llvm/ADT/StringMap.h"

namespace pepper {
    class Scope;
    class Struct;
    class Function;

    class Symbols {
      public:
        using Symbol = std::variant<Ref<Struct>, Ref<Function>>;

      private:
        llvm::StringMap<Symbol> Table;

      public:
        Symbols();

        const llvm::StringMap<Symbol>& table() const {
            return Table;
        }

        static Ref<Symbols> FromScope(Ref<Scope> scope);
    };
} // namespace pepper
