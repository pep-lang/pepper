
#pragma once

#include <string>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/SourceLocation.h"
#include "Core/String.h"
#include "Core/Vector.h"

namespace llvm {
    class Type;
}

namespace pepper::ast {

    struct TypeName {
        Ident Name;
        std::vector<TypeName> GenericArgs;

        TypeName(Ident name, const Vector<TypeName>& args = {})
            : Name(std::move(name))
            , GenericArgs(args.begin(), args.end()) {
        }

        TypeName(const TypeName&) = default;
        TypeName(TypeName&&) = default;
        TypeName& operator=(const TypeName&) = default;

        void replace(const Ident& genericParam, const TypeName& genericArg);

        operator std::string() const {
            return toString();
        }

        std::string toString() const;
    };

    struct Node {
        DECLARE_RTTI(Node);

        SourceLocation Source;

        Node() = default;
        virtual ~Node() = default;

        [[nodiscard]] std::string sourcePrefix(int width = -1, int indent = 0) const;
        [[nodiscard]] virtual std::string toString() const;
        [[nodiscard]] virtual std::string dump(int indent = 0) const;
    };

    // Placeholder in the l-value stack for nodes that haven't been constructed yet, but need to be
    // in the stack to cause r-values to be collected
    struct Pending : public Node {
        DECLARE_RTTI(Pending, Node);

        const RTTI* Type;
        Ref<Node> Value;

        template <typename N>
        explicit Pending(Ref<N> node) {
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

    struct Symbol : public Node {
        DECLARE_RTTI(Symbol, Node);

        TypeName Type;
        Ident Name;

      public:
        Symbol(const TypeName& type, const Ident& name)
            : Type(type)
            , Name(name) {
        }
    };

    class Expression : public Node {
        DECLARE_RTTI(Expression, Node);

      public:
        virtual const TypeName& type() const {
            static TypeName Void("void");
            return Void;
        }
    };
} // namespace pepper::ast