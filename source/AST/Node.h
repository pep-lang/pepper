
#pragma once

#include <string>

#include "Core/Common.h"
#include "Core/Name.h"
#include "Core/SourceLocation.h"
#include "Core/String.h"

namespace llvm {
    class Type;
}

namespace pepper::ast {

    class Node {
        DECLARE_RTTI(Node);

        SourceLocation Source;

      public:
        Node() = default;
        virtual ~Node() = default;

        std::string sourcePrefix() const {
            int width = Source.File.size() + 10;
            std::string src = Source.toString();
            std::string padding = repeat(" ", width - src.size());
            return llvm::formatv("{0}:{1}", Source.toString(), padding);
        }

        virtual std::string toString() const {
            return llvm::formatv("{0} {1}", sourcePrefix(), rtti()->name());
        }

        virtual std::string dump() const {
            return llvm::formatv("{0}: ", rtti()->name());
        }
    };

    class Pending : public Node {
        DECLARE_RTTI(Pending, Node);

        const RTTI* Type;
        Ref<Node> Value;

      public:
        template <typename N>
        Pending(Ref<N> node) {
            Value = node;
            Type = RTTI::of<N>();
        }
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