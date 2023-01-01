
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

        std::string sourcePrefix(int width = -1, int indent = 0) const {
            width = (width >= 0) ? width : Source.File.size() + 10;
            width += indent;
            std::string src = Source.toString();
            std::string padding = repeat(" ", width - src.size());
            return llvm::formatv("{0}:{1}", Source.toString(), padding);
        }

        virtual std::string toString() const {
            return llvm::formatv("{0}: ", rtti()->name());
        }

        virtual std::string dump(int indent = 0) const {
            return llvm::formatv("{0}: {1}: ", sourcePrefix(-1, indent), rtti()->name());
        }
    };

    // Placeholder in the l-value stack for nodes that haven't been constructed yet, but need to be
    // in the stack to cause r-values to be collected
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

        template <typename N, typename... Args>
        static Ref<Pending> New(Args&&... args) {
            if constexpr ((sizeof...(args)))
                return Ref<Pending>::New(Ref<N>::New(std::forward<Args>(args)...));
            return Ref<Pending>::New(Ref<N>());
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