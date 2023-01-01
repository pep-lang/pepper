//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <string>

#include "AST/Functions.h"
#include "AST/Node.h"
#include "AST/Variables.h"
#include "Core/Common.h"
#include "Core/Name.h"
#include "Core/Vector.h"

namespace pepper::ast {

    struct StructDef;

    struct FieldDef : public VariableDef {
        DECLARE_RTTI(FieldDef, VariableDef);

        Ref<StructDef> Struct;

        FieldDef(Ref<StructDef> st, const Name& type, const Name& name, Ref<Expression> defaultValue = nullptr);

        std::string toString() const override;
        std::string dump(int indent) const override;
    };

    struct MethodDef : public FunctionDef {
        DECLARE_RTTI(MethodDef, FunctionDef);

        Ref<StructDef> Struct;

      public:
        MethodDef(Ref<StructDef> st,
                  const Name& returnType,
                  const Name& name,
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

        StructDef(const Name& type, const Name& name);

        static Ref<StructDef> New(const Name& type, const Name& name);

        void finish();

        std::string toString() const override;
        std::string dump(int indent = 0) const override;
    };

    struct MemberRef : public Expression {
        DECLARE_RTTI(MemberRef, Expression);

        Ref<Expression> LHS;
        Name MemberName;

        MemberRef() = default;

        MemberRef(Ref<Expression> lhs, const Name& fieldName)
            : LHS(lhs)
            , MemberName(fieldName) {
        }

        const Name& type() const override {
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
        const Name MethodName;
        Vector<Ref<Expression>> Args;

        MethodCall(Ref<Expression> thisRef, const Name& methodName, const Vector<Ref<Expression>>& args = {})
            : This(thisRef)
            , MethodName(methodName)
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
            return Node::toString() + std::string(llvm::formatv("{0}*", Struct->Identifier));
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) + std::string(llvm::formatv("{0}*", Struct->Identifier));
        }
    };
} // namespace pepper::ast
