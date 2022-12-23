//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include "Core/Common.h"
#include "llvm/ADT/SmallVector.h"
#include <string>

namespace llvm {
    class Type;
    class Value;
} // namespace llvm

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
        StructDef(llvm::Type* type, std::string name)
            : Symbol(type, std::move(name)) {
        }

        void finish();
    };

    class MemberRef : public Expression {
        DECLARE_RTTI(MemberRef, Expression);

        llvm::Type* Type;
        Ref<Expression> LHS;
        const std::string Name;

      public:
        MemberRef(llvm::Type* type, Ref<Expression> lhs, const std::string& fieldName)
            : Type(type)
            , LHS(lhs)
            , Name(fieldName) {
        }

        llvm::Type* type() const override {
            return Type;
        }

        Ref<Expression> lhs() const {
            return LHS;
        }

        const std::string& name() const {
            return Name;
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
