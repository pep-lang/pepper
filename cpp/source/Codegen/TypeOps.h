//
// Created by Justin Boswell on 12/22/22.
//

#pragma once

#include "Core/Common.h"

namespace llvm {
    class Type;
    class Value;
} // namespace llvm

namespace pepper {
    class Type;
    class PointerType;
    class Symbol;

    namespace ast {
        class Symbol;
    } // namespace ast

    class TypeOps {
        DECLARE_RTTI(TypeOps);

      protected:
        llvm::Type* Type = nullptr;

      public:
        explicit TypeOps(llvm::Type* type)
            : Type(type) {
        }

        operator llvm::Type*() const {
            return Type;
        }

        static Ref<TypeOps> get(llvm::Type* type);

        virtual llvm::Value* coerce(llvm::Value* value) const = 0;

        virtual llvm::Value* add(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* sub(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* mul(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* div(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* mod(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* pow(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* less(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* lessEq(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* greater(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* greaterEq(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* lshift(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* rshift(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* equal(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* notEqual(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* assign(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* bitAnd(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* bitXor(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* bitOr(llvm::Value* lhs, llvm::Value* rhs) const;
        virtual llvm::Value* asBool(llvm::Value* value) const;
    };

    class UserType : public TypeOps {
        DECLARE_RTTI(UserType, TypeOps)
      public:
        UserType(const std::string& name, llvm::Type* type);
        ~UserType() = default;
    };
} // namespace pepper
