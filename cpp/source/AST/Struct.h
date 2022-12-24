//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <string>

#include "Core/Common.h"
#include "Core/Name.h"
#include "llvm/ADT/SmallVector.h"

namespace pepper::ast {
    class FieldDef;

    class StructDef : public Symbol {
        DECLARE_RTTI(StructDef, Symbol);

        Ref<FunctionDef> New;
        Ref<MethodDef> Initializer;
        Ref<MethodDef> Constructor;
        Ref<MethodDef> Destructor;
        llvm::SmallVector<Ref<FieldDef>> Fields;
        llvm::SmallVector<Ref<MethodDef>> Methods;

      public:
        StructDef(const Name& type, const Name& name)
            : Symbol(type, name) {
        }

        void finish();
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
    };
} // namespace pepper::ast
