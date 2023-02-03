
#pragma once

#include "AST/Node.h"
#include "Core/Common.h"
#include "Core/Ident.h"

namespace pepper::ast {
    struct BinaryOp : public Expression {
        DECLARE_RTTI(BinaryOp, Expression);

        TNodeRef<Expression> LHS;
        TNodeRef<Expression> RHS;

        BinaryOp(Expression* lhs, Expression* rhs)
            : LHS(lhs)
            , RHS(rhs) {}

        BinaryOp(const BinaryOp& rhs)
            : Expression(rhs)
            , LHS(rhs.LHS->cloneAs<Expression>())
            , RHS(rhs.RHS->cloneAs<Expression>()) {}

        const TypeName& type() const override {
            return TypeName::Widest(LHS->type(), RHS->type());
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

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(LHS);
            visitor.visit(RHS);
        }
    };

    struct Add : public BinaryOp {
        DECLARE_RTTI(Add, BinaryOp);
        AST_NODE_POD_CLONE(Add);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Sub : public BinaryOp {
        DECLARE_RTTI(Sub, BinaryOp);
        AST_NODE_POD_CLONE(Sub);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Mul : public BinaryOp {
        DECLARE_RTTI(Mul, BinaryOp);
        AST_NODE_POD_CLONE(Mul);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Div : public BinaryOp {
        DECLARE_RTTI(Div, BinaryOp);
        AST_NODE_POD_CLONE(Div);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Mod : public BinaryOp {
        DECLARE_RTTI(Mod, BinaryOp);
        AST_NODE_POD_CLONE(Mod);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Pow : public BinaryOp {
        DECLARE_RTTI(Pow, BinaryOp);
        AST_NODE_POD_CLONE(Pow);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Equal : public BinaryOp {
        DECLARE_RTTI(Equal, BinaryOp);
        AST_NODE_POD_CLONE(Equal);

        const TypeName& type() const override {
            return TypeName::Bool;
        }

      public:
        using BinaryOp::BinaryOp;
    };

    struct NotEqual : public BinaryOp {
        DECLARE_RTTI(NotEqual, BinaryOp);
        AST_NODE_POD_CLONE(NotEqual);

        const TypeName& type() const override {
            return TypeName::Bool;
        }

      public:
        using BinaryOp::BinaryOp;
    };

    struct Less : public BinaryOp {
        DECLARE_RTTI(Less, BinaryOp);
        AST_NODE_POD_CLONE(Less);

      public:
        using BinaryOp::BinaryOp;
    };

    struct LessEqual : public BinaryOp {
        DECLARE_RTTI(LessEqual, BinaryOp);
        AST_NODE_POD_CLONE(LessEqual);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Greater : public BinaryOp {
        DECLARE_RTTI(Greater, BinaryOp);
        AST_NODE_POD_CLONE(Greater);

      public:
        using BinaryOp::BinaryOp;
    };

    struct GreaterEqual : public BinaryOp {
        DECLARE_RTTI(GreaterEqual, BinaryOp);
        AST_NODE_POD_CLONE(GreaterEqual);

      public:
        using BinaryOp::BinaryOp;
    };

    struct LShift : public BinaryOp {
        DECLARE_RTTI(LShift, BinaryOp);
        AST_NODE_POD_CLONE(LShift);

      public:
        using BinaryOp::BinaryOp;
    };

    struct RShift : public BinaryOp {
        DECLARE_RTTI(RShift, BinaryOp);
        AST_NODE_POD_CLONE(RShift);

      public:
        using BinaryOp::BinaryOp;
    };

    struct BitAnd : public BinaryOp {
        DECLARE_RTTI(BitAnd, BinaryOp);
        AST_NODE_POD_CLONE(BitAnd);

      public:
        using BinaryOp::BinaryOp;
    };

    struct BitOr : public BinaryOp {
        DECLARE_RTTI(BitOr, BinaryOp);
        AST_NODE_POD_CLONE(BitOr);

      public:
        using BinaryOp::BinaryOp;
    };

    struct BitXor : public BinaryOp {
        DECLARE_RTTI(BitXor, BinaryOp);
        AST_NODE_POD_CLONE(BitXor);

      public:
        using BinaryOp::BinaryOp;
    };

    struct LogicalAnd : public BinaryOp {
        DECLARE_RTTI(LogicalAnd, BinaryOp);
        AST_NODE_POD_CLONE(LogicalAnd);

      public:
        using BinaryOp::BinaryOp;
    };

    struct LogicalOr : public BinaryOp {
        DECLARE_RTTI(LogicalOr, BinaryOp);
        AST_NODE_POD_CLONE(LogicalOr);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Assign : public BinaryOp {
        DECLARE_RTTI(Assign, BinaryOp);
        AST_NODE_POD_CLONE(Assign);

      public:
        Assign(Expression* lhs = nullptr, Expression* rhs = nullptr)
            : BinaryOp(lhs, rhs) {}
    };

    struct CompoundAssign : public Assign {
        DECLARE_RTTI(CompoundAssign, Assign);

      public:
        using Assign::Assign;
    };

    struct AddAssign : public CompoundAssign {
        DECLARE_RTTI(AddAssign, CompoundAssign);
        AST_NODE_POD_CLONE(AddAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct SubAssign : public CompoundAssign {
        DECLARE_RTTI(SubAssign, CompoundAssign);
        AST_NODE_POD_CLONE(SubAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct MulAssign : public CompoundAssign {
        DECLARE_RTTI(MulAssign, CompoundAssign);
        AST_NODE_POD_CLONE(MulAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct DivAssign : public CompoundAssign {
        DECLARE_RTTI(DivAssign, CompoundAssign);
        AST_NODE_POD_CLONE(DivAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct ModAssign : public CompoundAssign {
        DECLARE_RTTI(ModAssign, CompoundAssign);
        AST_NODE_POD_CLONE(ModAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct LShiftAssign : public CompoundAssign {
        DECLARE_RTTI(LShiftAssign, CompoundAssign);
        AST_NODE_POD_CLONE(LShiftAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct RShiftAssign : public CompoundAssign {
        DECLARE_RTTI(RShiftAssign, CompoundAssign);
        AST_NODE_POD_CLONE(RShiftAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct BitAndAssign : public CompoundAssign {
        DECLARE_RTTI(BitAndAssign, CompoundAssign);
        AST_NODE_POD_CLONE(BitAndAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct BitOrAssign : public CompoundAssign {
        DECLARE_RTTI(BitOrAssign, CompoundAssign);
        AST_NODE_POD_CLONE(BitOrAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct BitXorAssign : public CompoundAssign {
        DECLARE_RTTI(BitXorAssign, CompoundAssign);
        AST_NODE_POD_CLONE(BitXorAssign);

      public:
        using CompoundAssign::CompoundAssign;
    };

    struct Index : public Expression {
        DECLARE_RTTI(Index, Expression);
        AST_NODE_POD_CLONE(Index);

        TNodeRef<Expression> LHS;
        TNodeRef<Expression> IndexExpr;

      public:
        Index(Expression* lhs = nullptr, Expression* indexExpr = nullptr)
            : LHS(lhs)
            , IndexExpr(indexExpr) {}

        const TypeName& type() const override {
            return LHS->type();
        }

        std::string toString() const override {
            return llvm::formatv("{0} {1}[{2}]",
                                 Node::toString(),
                                 LHS ? LHS->toString() : "None",
                                 IndexExpr ? IndexExpr->toString() : "??");
        }

        std::string dump(int indent) const override {
            return llvm::formatv(
                "{0} {1}[{2}]", Node::dump(indent), LHS ? LHS->dump() : "None", IndexExpr ? IndexExpr->dump() : "??");
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(LHS);
            visitor.visit(IndexExpr);
        }
    };
} // namespace pepper::ast