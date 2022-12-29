
#pragma once

#include "AST/Node.h"
#include "Core/Common.h"
#include "Core/Name.h"

namespace pepper::ast {
    class BinaryOp : public Expression {
        DECLARE_RTTI(BinaryOp, Expression);

      protected:
        Ref<Expression> LHS;
        Ref<Expression> RHS;

      public:
        BinaryOp(Ref<Expression> lhs, Ref<Expression> rhs)
            : LHS(lhs)
            , RHS(rhs) {
        }

        Ref<Expression> lhs() const {
            return LHS;
        }

        void setLhs(Ref<Expression> newLhs) {
            LHS = newLhs;
        }

        Ref<Expression> rhs() const {
            return RHS;
        }

        void setRhs(Ref<Expression> newRhs) {
            RHS = newRhs;
        }

        std::string toString() const override {
            auto str = Node::toString();
            if (LHS && RHS) {
                str += std::string(llvm::formatv("({0}), ({1})", LHS->toString(), RHS->toString()));
            }
            return str;
        }

        std::string dump() const override {
            return Node::toString() +
                   std::string(
                       llvm::formatv("({0}), ({1})", LHS ? LHS->toString() : "empty", RHS ? RHS->toString() : "empty"));
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

    class Assign : public BinaryOp {
        DECLARE_RTTI(Assign, BinaryOp);

      public:
        Assign(Ref<Expression> lhs = nullptr, Ref<Expression> rhs = nullptr)
            : BinaryOp(lhs, rhs) {
        }
    };

    class CompoundAssign : public Assign {
        DECLARE_RTTI(CompoundAssign, Assign);

      public:
        using Assign::Assign;
    };

    class AddAssign : public CompoundAssign {
        DECLARE_RTTI(AddAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    class SubAssign : public CompoundAssign {
        DECLARE_RTTI(SubAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    class MulAssign : public CompoundAssign {
        DECLARE_RTTI(MulAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    class DivAssign : public CompoundAssign {
        DECLARE_RTTI(DivAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    class ModAssign : public CompoundAssign {
        DECLARE_RTTI(ModAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    class LShiftAssign : public CompoundAssign {
        DECLARE_RTTI(LShiftAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    class RShiftAssign : public CompoundAssign {
        DECLARE_RTTI(RShiftAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    class BitAndAssign : public CompoundAssign {
        DECLARE_RTTI(BitAndAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    class BitOrAssign : public CompoundAssign {
        DECLARE_RTTI(BitOrAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    class BitXorAssign : public CompoundAssign {
        DECLARE_RTTI(BitXorAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };
} // namespace pepper::ast