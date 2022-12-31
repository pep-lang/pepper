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

    class StructDef;

    class FieldDef : public VariableDef {
        DECLARE_RTTI(FieldDef, VariableDef);

      public:
        Ref<StructDef> Struct;

        FieldDef(Ref<StructDef> st, const Name& type, const Name& name, Ref<Expression> defaultValue = nullptr);

        std::string toString() const override;
        std::string dump() const override;
    };

    class MethodDef : public FunctionDef {
        DECLARE_RTTI(MethodDef, FunctionDef);

      private:
        Ref<StructDef> Struct;

      public:
        MethodDef(Ref<StructDef> st,
                  const Name& returnType,
                  const Name& name,
                  const Params& params = Params(),
                  bool vararg = false);

        [[nodiscard]] Ref<StructDef> structDef() const {
            return Struct;
        }

        std::string toString() const override;
        std::string dump() const override;
    };

    class StructDef
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

      public:
        static Ref<StructDef> New(const Name& type, const Name& name);

        void finish();

        std::string toString() const override;
        std::string dump() const override;
    };

    class MemberRef : public Expression {
        DECLARE_RTTI(MemberRef, Expression);

        Ref<Expression> LHS;
        Name MemberName;

      public:
        MemberRef() = default;

        MemberRef(Ref<Expression> lhs, const Name& fieldName)
            : LHS(lhs)
            , MemberName(fieldName) {
        }

        const Name& type() const override {
            return LHS->type();
        }

        Ref<Expression> lhs() const {
            return LHS;
        }

        const Name& name() const {
            return MemberName;
        }

        std::string toString() const override {
            return Node::toString() +
                   std::string(llvm::formatv("({0}).{1}", LHS ? LHS->toString() : "unknown", MemberName));
        }

        std::string dump() const override {
            return toString();
        }
    };

    class MethodCall : public Expression {
        DECLARE_RTTI(MethodCall, Expression);

        Ref<Expression> This;
        const Name MethodName;
        Vector<Ref<Expression>> Args;

      public:
        MethodCall(Ref<Expression> thisRef, const Name& methodName, const Vector<Ref<Expression>>& args = {})
            : This(thisRef)
            , MethodName(methodName)
            , Args(args) {
        }
    };

    class ThisRef : public Expression {
        DECLARE_RTTI(ThisRef, Expression);

      private:
        Ref<StructDef> ThisDef;

      public:
        ThisRef(Ref<StructDef> thisType)
            : ThisDef(thisType) {
        }

        Ref<StructDef> thisDef() const {
            return ThisDef;
        }

        std::string toString() const override {
            return Node::toString() + std::string(llvm::formatv("{0}*", ThisDef->identifier()));
        }

        std::string dump() const override {
            return toString();
        }
    };
} // namespace pepper::ast
