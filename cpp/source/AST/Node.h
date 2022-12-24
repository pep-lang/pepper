
#pragma once

#include <string>

#include "Core/Common.h"
#include "Core/Name.h"

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
        Name Type;
        Name Identifier;

      public:
        Symbol(const Name& type, const Name& name)
            : Type(type)
            , Identifier(name) {
        }

        [[nodiscard]] const Name& type() const {
            return Type;
        }

        [[nodiscard]] const Name& identifier() const {
            return Identifier;
        }
    };

    class Expression : public Node {
        DECLARE_RTTI(Expression, Node);

      public:
        virtual const Name& type() const {
            static Name Void("void");
            return Void;
        }
    };
} // namespace pepper::ast