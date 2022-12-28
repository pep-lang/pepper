//
// Created by Justin Boswell on 12/22/22.
//

#pragma once

#include "Codegen/IR/Value.h"
#include "Core/Common.h"

namespace llvm {
    class Type;
    class Value;
} // namespace llvm

namespace pepper {
    class TypeInfo;
    class PointerType;

    class TypeOps {
        DECLARE_RTTI(TypeOps);

      protected:
        Ref<TypeInfo> Type = nullptr;

      public:
        explicit TypeOps(Ref<TypeInfo> type)
            : Type(type) {
        }

        operator llvm::Type*() const {
            return Type->llvmType();
        }

        static Ref<TypeOps> get(Ref<TypeInfo> type);
        static Ref<TypeOps> get(const TypeInfo* type);

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
        virtual Value asBool(Value value) const;
    };

    class UserType : public TypeOps {
        DECLARE_RTTI(UserType, TypeOps)
      public:
        UserType(const std::string& name, Ref<TypeInfo> type);
        ~UserType() = default;
    };
} // namespace pepper
