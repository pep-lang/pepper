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

    class Operations {
        DECLARE_RTTI(Operations);

      protected:
        Ref<Type> Ty = nullptr;

      public:
        explicit Operations(Ref<Type> type)
            : Ty(type) {
        }

        operator llvm::Type*() const {
            return Ty->llvmType();
        }

        Ref<Type> type() const {
            return Ty;
        }

        static Ref<Operations> get(Ref<Type> type);
        static Ref<Operations> get(const Type* type);

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
        virtual void init(Value lhs, Value rhs) const;
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

    class NativeOperations : public Operations {
        DECLARE_RTTI(NativeOperations, Operations)

      public:
        NativeOperations(Ref<Type> type)
            : Operations(type) {
        }
    };

    class PointerOperations : public NativeOperations {
        DECLARE_RTTI(PointerOperations, NativeOperations)
      public:
        PointerOperations(Ref<Type> type)
            : NativeOperations(type) {
        }

        Value coerce(Value value) const override;
        Value equal(Value lhs, Value rhs) const override;
        Value notEqual(Value lhs, Value rhs) const override;
        Value assign(Value lhs, Value rhs) const override;
        Value asBool(Value value) const override;
        Value logicalNot(Value value) const override;
    };
} // namespace pepper
