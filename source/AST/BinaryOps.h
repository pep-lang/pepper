
#pragma once

#include "AST/Node.h"
#include "Core/Common.h"
#include "Core/Ident.h"

namespace pepper::ast {
    struct BinaryOp : public Expression {
        DECLARE_RTTI(BinaryOp, Expression);

        Ref<Expression> LHS;
        Ref<Expression> RHS;

        BinaryOp(Ref<Expression> lhs, Ref<Expression> rhs)
            : LHS(lhs)
            , RHS(rhs) {
        }

        std::string toString() const override {
            auto str = Node::toString();
            if (LHS && RHS) {
                str += std::string(llvm::formatv("({0}), ({1})", LHS->toString(), RHS->toString()));
            }
            return str;
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) +
                   std::string(llvm::formatv("({0}), ({1})", LHS ? LHS->dump() : "empty", RHS ? RHS->dump() : "empty"));
        }
    };

    struct Add : public BinaryOp {
        DECLARE_RTTI(Add, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Sub : public BinaryOp {
        DECLARE_RTTI(Sub, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Mul : public BinaryOp {
        DECLARE_RTTI(Mul, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Div : public BinaryOp {
        DECLARE_RTTI(Div, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Mod : public BinaryOp {
        DECLARE_RTTI(Mod, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Pow : public BinaryOp {
        DECLARE_RTTI(Pow, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Equal : public BinaryOp {
        DECLARE_RTTI(Equal, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct NotEqual : public BinaryOp {
        DECLARE_RTTI(NotEqual, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Less : public BinaryOp {
        DECLARE_RTTI(Less, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct LessEqual : public BinaryOp {
        DECLARE_RTTI(LessEqual, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Greater : public BinaryOp {
        DECLARE_RTTI(Greater, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct GreaterEqual : public BinaryOp {
        DECLARE_RTTI(GreaterEqual, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct LShift : public BinaryOp {
        DECLARE_RTTI(LShift, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct RShift : public BinaryOp {
        DECLARE_RTTI(RShift, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct BitAnd : public BinaryOp {
        DECLARE_RTTI(BitAnd, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct BitOr : public BinaryOp {
        DECLARE_RTTI(BitOr, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct BitXor : public BinaryOp {
        DECLARE_RTTI(BitXor, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct LogicalAnd : public BinaryOp {
        DECLARE_RTTI(LogicalAnd, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct LogicalOr : public BinaryOp {
        DECLARE_RTTI(LogicalOr, BinaryOp);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Assign : public BinaryOp {
        DECLARE_RTTI(Assign, BinaryOp);

      public:
        Assign(Ref<Expression> lhs = nullptr, Ref<Expression> rhs = nullptr)
            : BinaryOp(lhs, rhs) {
        }
    };

    struct CompoundAssign : public Assign {
        DECLARE_RTTI(CompoundAssign, Assign);

      public:
        using Assign::Assign;
    };

    struct AddAssign : public CompoundAssign {
        DECLARE_RTTI(AddAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct SubAssign : public CompoundAssign {
        DECLARE_RTTI(SubAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct MulAssign : public CompoundAssign {
        DECLARE_RTTI(MulAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct DivAssign : public CompoundAssign {
        DECLARE_RTTI(DivAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct ModAssign : public CompoundAssign {
        DECLARE_RTTI(ModAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct LShiftAssign : public CompoundAssign {
        DECLARE_RTTI(LShiftAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct RShiftAssign : public CompoundAssign {
        DECLARE_RTTI(RShiftAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct BitAndAssign : public CompoundAssign {
        DECLARE_RTTI(BitAndAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct BitOrAssign : public CompoundAssign {
        DECLARE_RTTI(BitOrAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct BitXorAssign : public CompoundAssign {
        DECLARE_RTTI(BitXorAssign, CompoundAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };
} // namespace pepper::ast