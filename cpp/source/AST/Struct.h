//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <string>

#include "Core/Common.h"
#include "Core/Name.h"
#include "Core/Vector.h"

namespace pepper::ast {
    class FieldDef;
    class FunctionDef;
    class MethodDef;

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
    };

    class MemberRef : public Expression {
        DECLARE_RTTI(MemberRef, Expression);

        Ref<Expression> LHS;
        const Name MemberName;

      public:
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
            return Node::toString() + std::string(llvm::formatv("({0}).{1}", LHS->toString(), MemberName));
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
    };
} // namespace pepper::ast
