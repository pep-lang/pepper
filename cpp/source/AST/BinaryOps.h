
#pragma once

#include "AST/Node.h"
#include "Core/Common.h"

namespace llvm {
    class Type;
    class Value;
} // namespace llvm

namespace pepper::ast {
    class BinaryOp : public Expression {
        DECLARE_RTTI(BinaryOp, Expression);

      public:
        Ref<Expression> LHS;
        Ref<Expression> RHS;

        llvm::Type* type() const override {
            return operandType();
        }

        virtual llvm::Type* operandType() const;
        virtual llvm::Value* op(llvm::Value*, llvm::Value*) const = 0;

        BinaryOp(Ref<Expression> lhs, Ref<Expression> rhs)
            : LHS(lhs)
            , RHS(rhs) {
        }
    };

    class Add : public BinaryOp {
        DECLARE_RTTI(Add, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class Sub : public BinaryOp {
        DECLARE_RTTI(Sub, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class Mul : public BinaryOp {
        DECLARE_RTTI(Mul, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class Div : public BinaryOp {
        DECLARE_RTTI(Div, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class Mod : public BinaryOp {
        DECLARE_RTTI(Mod, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class Pow : public BinaryOp {
        DECLARE_RTTI(Pow, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class Equal : public BinaryOp {
        DECLARE_RTTI(Equal, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class NotEqual : public BinaryOp {
        DECLARE_RTTI(NotEqual, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class Less : public BinaryOp {
        DECLARE_RTTI(Less, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class LessEqual : public BinaryOp {
        DECLARE_RTTI(LessEqual, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class Greater : public BinaryOp {
        DECLARE_RTTI(Greater, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class GreaterEqual : public BinaryOp {
        DECLARE_RTTI(GreaterEqual, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class Assign : public BinaryOp {
        DECLARE_RTTI(Assign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class LShift : public BinaryOp {
        DECLARE_RTTI(LShift, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class RShift : public BinaryOp {
        DECLARE_RTTI(RShift, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class BitAnd : public BinaryOp {
        DECLARE_RTTI(BitAnd, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class BitOr : public BinaryOp {
        DECLARE_RTTI(BitOr, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class BitXor : public BinaryOp {
        DECLARE_RTTI(BitXor, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class LogicalAnd : public BinaryOp {
        DECLARE_RTTI(LogicalAnd, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class LogicalOr : public BinaryOp {
        DECLARE_RTTI(LogicalOr, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class CompoundAssign : public BinaryOp {
        DECLARE_RTTI(CompoundAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class AddAssign : public BinaryOp {
        DECLARE_RTTI(AddAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class SubAssign : public BinaryOp {
        DECLARE_RTTI(SubAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class MulAssign : public BinaryOp {
        DECLARE_RTTI(MulAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class DivAssign : public BinaryOp {
        DECLARE_RTTI(DivAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class ModAssign : public BinaryOp {
        DECLARE_RTTI(ModAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class LShiftAssign : public BinaryOp {
        DECLARE_RTTI(LShiftAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class RShiftAssign : public BinaryOp {
        DECLARE_RTTI(RShiftAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class BitAndAssign : public BinaryOp {
        DECLARE_RTTI(BitAndAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class BitOrAssign : public BinaryOp {
        DECLARE_RTTI(BitOrAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    class BitXorAssign : public BinaryOp {
        DECLARE_RTTI(BitXorAssign, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };
} // namespace pepper::ast