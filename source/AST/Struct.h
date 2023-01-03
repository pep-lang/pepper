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

        Ref<StructDef> Struct;

        FieldDef(Ref<StructDef> st, const TypeName& type, const Ident& name, Ref<Expression> defaultValue = nullptr);

        std::string toString() const override;
        std::string dump(int indent) const override;
    };

    struct MethodDef : public FunctionDef {
        DECLARE_RTTI(MethodDef, FunctionDef);

        Ref<StructDef> Struct;

      public:
        MethodDef(Ref<StructDef> st,
                  const TypeName& returnType,
                  const Ident& name,
                  const Params& params = Params(),
                  bool vararg = false);

        std::string toString() const override;
        std::string dump(int indent) const override;
    };

    struct StructDef
        : public Symbol
        , public std::enable_shared_from_this<StructDef> {
        DECLARE_RTTI(StructDef, Symbol);

        Ref<FunctionDef> NewInstance;
        Ref<MethodDef> Initializer;
        Ref<MethodDef> Constructor;
        Ref<MethodDef> Destructor;
        Vector<Ref<FieldDef>> Fields;
        Vector<Ref<MethodDef>> Methods;
        // type parameters in struct decl
        Vector<Ident> GenericParams;
        // generic struct that this struct is a specialization of
        Ref<StructDef> GenericStruct;
        // generic args for this specialization
        Vector<TypeName> GenericArgs;

        StructDef(const TypeName& type, const Ident& name);

        void specialize(Ref<StructDef> genericStruct, Vector<TypeName> genericArgs);
        void finish();

        static Ref<StructDef> New(const TypeName& type, const Ident& name);

        std::string toString() const override;
        std::string dump(int indent = 0) const override;
    };

    struct MemberRef : public Expression {
        DECLARE_RTTI(MemberRef, Expression);

        Ref<Expression> LHS;
        Ident MemberName;

        MemberRef() = default;

        MemberRef(Ref<Expression> lhs, const Ident& fieldName)
            : LHS(lhs)
            , MemberName(fieldName) {
        }

        const TypeName& type() const override {
            return LHS->type();
        }

        std::string toString() const override {
            return Node::toString() +
                   std::string(llvm::formatv("({0}).{1}", LHS ? LHS->toString() : "unknown", MemberName));
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) +
                   std::string(llvm::formatv("({0}).{1}", LHS ? LHS->toString() : "unknown", MemberName));
        }
    };

    struct MethodCall : public Expression {
        DECLARE_RTTI(MethodCall, Expression);

        Ref<Expression> This;
        const Ident Name;
        Vector<Ref<Expression>> Args;

        MethodCall(Ref<Expression> thisRef, const Ident& methodName, const Vector<Ref<Expression>>& args = {})
            : This(thisRef)
            , Name(methodName)
            , Args(args) {
        }
    };

    struct ThisRef : public Expression {
        DECLARE_RTTI(ThisRef, Expression);

        Ref<StructDef> Struct;

        ThisRef(Ref<StructDef> thisType)
            : Struct(thisType) {
        }

        std::string toString() const override {
            return Node::toString() + std::string(llvm::formatv("{0}*", Struct->Name));
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) + std::string(llvm::formatv("{0}*", Struct->Name));
        }
    };
} // namespace pepper::ast
