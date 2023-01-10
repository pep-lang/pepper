//
// Created by Justin Boswell on 12/22/22.
//

#pragma once

#include "CodeGen/Value.h"
#include "Core/Common.h"

namespace llvm {
    class Type;
    class Value;
} // namespace llvm

namespace pepper {

    class TypeOps {
        DECLARE_RTTI(TypeOps);

      protected:
        Ref<Type> Ty = nullptr;

      public:
        explicit TypeOps(Ref<Type> type)
            : Ty(type) {
        }

        operator llvm::Type*() const {
            return Ty->llvmType();
        }

        Ref<Type> type() const {
            return Ty;
        }

        static Ref<TypeOps> get(Ref<Type> type);
        static Ref<TypeOps> get(const Type* type);

        virtual Value coerce(Value value) const = 0;

        virtual Value add(Value lhs, Value rhs) const;
        virtual Value sub(Value lhs, Value rhs) const;
        virtual Value mul(Value lhs, Value rhs) const;
        virtual Value div(Value lhs, Value rhs) const;
        virtual Value mod(Value lhs, Value rhs) const;
        virtual Value pow(Value lhs, Value rhs) const;
        virtual Value less(Value lhs, Value rhs) const;
        virtual Value lessEq(Value lhs, Value rhs) const;
        virtual Value greater(Value lhs, Value rhs) const;
        virtual Value greaterEq(Value lhs, Value rhs) const;
        virtual Value lshift(Value lhs, Value rhs) const;
        virtual Value rshift(Value lhs, Value rhs) const;
        virtual Value equal(Value lhs, Value rhs) const;
        virtual Value notEqual(Value lhs, Value rhs) const;
        virtual Value assign(Value lhs, Value rhs) const;
        virtual Value bitAnd(Value lhs, Value rhs) const;
        virtual Value bitXor(Value lhs, Value rhs) const;
        virtual Value bitOr(Value lhs, Value rhs) const;
        virtual Value neg(Value val) const;
        virtual Value pos(Value val) const;
        virtual Value preIncrement(Value val) const;
        virtual Value preDecrement(Value val) const;
        virtual Value postIncrement(Value val) const;
        virtual Value postDecrement(Value val) const;
        virtual Value bitNot(Value val) const;
        virtual Value logicalNot(Value val) const;
        virtual Value asBool(Value value) const;
    };

} // namespace pepper
