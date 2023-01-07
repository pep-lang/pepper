//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <string>

#include "AST/Functions.h"
#include "AST/Node.h"
#include "AST/Variables.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper::ast {

    struct StructDef;

    struct FieldDef : public VariableDef {
        DECLARE_RTTI(FieldDef, VariableDef);

        StructDef* Struct;

        FieldDef(StructDef* st, const TypeName& type, const Ident& name, Ref<Expression> defaultValue = nullptr);

        Ref<Node> clone() const override;
        void specialize(const Specialization& spec) override;

        std::string toString() const override;
        std::string dump(int indent) const override;
    };

    struct MethodDef : public FunctionDef {
        DECLARE_RTTI(MethodDef, FunctionDef);

        StructDef* Struct;

      public:
        MethodDef(StructDef* st,
                  const TypeName& returnType,
                  const Ident& name,
                  const Params& params = Params(),
                  bool vararg = false);

        Ref<Node> clone() const override;
        void specialize(const Specialization& spec) override;

        std::string toString() const override;
        std::string dump(int indent) const override;
    };

    struct StructDef
        : public Symbol
        , public std::enable_shared_from_this<StructDef> {
        DECLARE_RTTI(StructDef, Symbol);
        AST_NODE_POD_CLONE(StructDef);

        Ref<FunctionDef> NewInstance;
        Ref<MethodDef> Initializer;
        Ref<MethodDef> Constructor;
        Ref<MethodDef> Destructor;
        Ref<MethodDef> Acquire;
        Ref<MethodDef> Release;
        Vector<Ref<FieldDef>> Fields;
        Vector<Ref<MethodDef>> Methods;
        // type parameters in struct decl
        Vector<Ident> GenericParams;
        // generic struct that this struct is a specialization of
        Ref<StructDef> GenericStruct;
        // generic args for this specialization
        Vector<TypeName> GenericArgs;

        explicit StructDef(const TypeName& type);
        StructDef(const StructDef& rhs);

        void specialize(Ref<StructDef> genericStruct, Vector<TypeName> genericArgs);
        void finish();

        static Ref<StructDef> New(const TypeName& type);

        Ref<FieldDef> getField(const Ident& name) const;
        Ref<MethodDef> getMethod(const Ident& name) const;

        std::string toString() const override;
        std::string dump(int indent = 0) const override;
    };

    struct MemberRef : public SymbolRef {
        DECLARE_RTTI(MemberRef, SymbolRef);
        AST_NODE_POD_CLONE(MemberRef);

        Ref<Expression> LHS;

        MemberRef(Ref<Expression> lhs, const Ident& fieldName)
            : SymbolRef(fieldName)
            , LHS(lhs) {
        }

        const TypeName& type() const override {
            return LHS->type();
        }

        std::string toString() const override {
            return Node::toString() +
                   std::string(llvm::formatv("({0}).{1}", LHS ? LHS->toString() : "unknown", identifier()));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} ({1}).{2}", Node::dump(indent), LHS ? LHS->dump() : "unknown", identifier());
        }

        void specialize(const Specialization& spec) override {
            LHS->specialize(spec);
        }
    };

    struct MethodCall : public Expression {
        DECLARE_RTTI(MethodCall, Expression);
        AST_NODE_POD_CLONE(MethodCall);

        TypeName Type;
        Ref<Expression> This;
        const Ident Name;
        Vector<Ref<Expression>> Args;

        MethodCall(const TypeName& type,
                   Ref<Expression> thisRef,
                   const Ident& methodName,
                   const Vector<Ref<Expression>>& args = {})
            : Type(type)
            , This(thisRef)
            , Name(methodName)
            , Args(args) {
        }

        const TypeName& type() const override {
            return Type;
        }

        void specialize(const Specialization& spec) override;

        std::string dump(int indent) const override;
    };

    struct ThisRef : public SymbolRef {
        DECLARE_RTTI(ThisRef, SymbolRef);
        AST_NODE_POD_CLONE(ThisRef);

        ThisRef()
            : SymbolRef("this") {
        }
    };
} // namespace pepper::ast
