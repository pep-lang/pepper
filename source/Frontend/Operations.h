//
// Created by Justin Boswell on 12/22/22.
//

#pragma once

#include "CodeGen/Address.h"
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

        virtual Address coerce(Address value) const = 0;

        virtual Address add(Address lhs, Address rhs) const;
        virtual Address sub(Address lhs, Address rhs) const;
        virtual Address mul(Address lhs, Address rhs) const;
        virtual Address div(Address lhs, Address rhs) const;
        virtual Address mod(Address lhs, Address rhs) const;
        virtual Address pow(Address lhs, Address rhs) const;
        virtual Address less(Address lhs, Address rhs) const;
        virtual Address lessEq(Address lhs, Address rhs) const;
        virtual Address greater(Address lhs, Address rhs) const;
        virtual Address greaterEq(Address lhs, Address rhs) const;
        virtual Address lshift(Address lhs, Address rhs) const;
        virtual Address rshift(Address lhs, Address rhs) const;
        virtual Address equal(Address lhs, Address rhs) const;
        virtual Address notEqual(Address lhs, Address rhs) const;
        virtual void init(Address lhs, Address rhs) const;
        virtual Address assign(Address lhs, Address rhs) const;
        virtual Address bitAnd(Address lhs, Address rhs) const;
        virtual Address bitXor(Address lhs, Address rhs) const;
        virtual Address bitOr(Address lhs, Address rhs) const;
        virtual Address neg(Address val) const;
        virtual Address pos(Address val) const;
        virtual Address preIncrement(Address val) const;
        virtual Address preDecrement(Address val) const;
        virtual Address postIncrement(Address val) const;
        virtual Address postDecrement(Address val) const;
        virtual Address bitNot(Address val) const;
        virtual Address logicalNot(Address val) const;
        virtual Address asBool(Address value) const;
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

        Address coerce(Address value) const override;
        Address equal(Address lhs, Address rhs) const override;
        Address notEqual(Address lhs, Address rhs) const override;
        Address assign(Address lhs, Address rhs) const override;
        Address asBool(Address value) const override;
        Address logicalNot(Address value) const override;
    };
} // namespace pepper
