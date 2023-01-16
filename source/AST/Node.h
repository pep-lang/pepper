
#pragma once

#include <string>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/SourceLocation.h"
#include "Core/String.h"
#include "Core/Vector.h"
#include "llvm/ADT/StringMap.h"

namespace llvm {
    class Type;
}

namespace pepper::ast {

    struct Specialization {
        DECLARE_RTTI(Specialization);
        using GenericTypeMap = llvm::StringMap<struct TypeName>;
        GenericTypeMap TypeMap;

      protected:
        Specialization() = default;
    };

    struct StructSpecialization : public Specialization {
        DECLARE_RTTI(StructSpecialization, Specialization);
        Ref<struct StructDef> Struct;

        StructSpecialization(Ref<struct StructDef> structDef)
            : Struct(structDef) {
        }
    };

    struct FunctionSpecialization : public Specialization {
        DECLARE_RTTI(FunctionSpecialization, Specialization);
        Ref<struct FunctionDef> Function;

        FunctionSpecialization(Ref<struct FunctionDef> function)
            : Function(function) {
        }
    };

    struct TypeName {
        Ident Name;
        std::vector<TypeName> GenericTypes;

        TypeName(Ident name = "default", const Vector<TypeName>& types = {})
            : Name(std::move(name))
            , GenericTypes(types.begin(), types.end()) {
        }

        TypeName(const TypeName&) = default;
        TypeName(TypeName&&) = default;
        TypeName& operator=(const TypeName&) = default;

        void replace(const Ident& genericParam, const TypeName& genericArg);
        void specialize(const Specialization::GenericTypeMap& map);

        operator std::string() const {
            return toString();
        }

        bool operator==(const TypeName& rhs) const {
            return Name == rhs.Name && GenericTypes == rhs.GenericTypes;
        }

        bool operator!=(const TypeName& rhs) const {
            return !(*this == rhs);
        }

        std::string toString() const;

        static const TypeName& Widest(const TypeName& lhs, const TypeName& rhs);

        static const TypeName Void;
        static const TypeName Auto;
        static const TypeName Bool;

        static const TypeName VoidPtr;
        static const TypeName Int8;
        static const TypeName UInt8;
        static const TypeName Int32;
        static const TypeName UInt32;
        static const TypeName Int64;
        static const TypeName UInt64;
        static const TypeName Double;
        static const TypeName Float;
    };

    struct Node {
        DECLARE_RTTI(Node);

        SourceLocation Source;

        Node() = default;
        virtual ~Node() = default;

        template <typename N>
        Ref<N> cloneAs() const {
            auto copy = Ref<N>{clone()};
            copy->Source = Source;
            return copy;
        }

        virtual Ref<Node> clone() const;

        virtual void specialize(const Specialization& spec) {
        }

        [[nodiscard]] std::string source(int width = -1, int indent = 0, const char* sep = "") const;
        [[nodiscard]] virtual std::string toString() const;
        [[nodiscard]] virtual std::string dump(int indent = 0) const;
    };

    // NOOP
    struct None : public Node {
        DECLARE_RTTI(None, Node);
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
        bool Hidden = false;

      public:
        Symbol(const TypeName& type, const Ident& name, bool hidden = false)
            : Type(type)
            , Name(name)
            , Hidden(hidden) {
        }

        void specialize(const Specialization& spec) override;
    };

    class Expression : public Node {
        DECLARE_RTTI(Expression, Node);

      public:
        virtual const TypeName& type() const {
            static TypeName Auto("__auto");
            return Auto;
        }
    };
} // namespace pepper::ast

#define AST_NODE_POD_CLONE(N)                                                                                          \
    inline Ref<Node> clone() const override {                                                                          \
        return Ref<Node>{static_cast<const RttiInstance<N>*>(rtti())->clone(this)};                                    \
    }
