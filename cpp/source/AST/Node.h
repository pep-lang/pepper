
#pragma once

#include "Core/Common.h"
#include <string>

namespace llvm {
    class Type;
}

namespace pepper::ast {

    class Node {
        DECLARE_RTTI(Node);

      public:
        Node() = default;
        virtual ~Node() = default;
    };

    class Symbol : public Node {
        DECLARE_RTTI(Symbol, Node);

      private:
        llvm::Type* Type;
        std::string Identifier;

      public:
        Symbol(llvm::Type* type, std::string name)
            : Type(type)
            , Identifier(std::move(name)) {
        }

        llvm::Type* type() const {
            return Type;
        }

        [[nodiscard]] const std::string& identifier() const {
            return Identifier;
        }
    };

    class Expression : public Node {
        DECLARE_RTTI(Expression, Node);

      public:
        [[nodiscard]] virtual llvm::Type* type() const = 0;
    };
} // namespace pepper::ast