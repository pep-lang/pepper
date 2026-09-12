
#pragma once

#include "Sema/Model/Node.h"
#include "Sema/Model/Visitor.h"
#include "Core/Common.h"
#include "Core/Exceptions.h"
#include "Core/Ident.h"

namespace pepper::sema {
    struct BinaryOp : public Expression {
        DECLARE_RTTI(BinaryOp, Expression);

        TNodeRef<Expression> lhs;
        TNodeRef<Expression> rhs;

        BinaryOp(Expression* lhs, Expression* rhs)
            : lhs(lhs)
            , rhs(rhs) {}

        BinaryOp(const BinaryOp& rhs)
            : Expression(rhs)
            , lhs(rhs.lhs->clone_as<Expression>())
            , rhs(rhs.rhs->clone_as<Expression>()) {}

        const TypeName& type() const override {
            if (lhs->type().is_numeric() && rhs->type().is_numeric())
                return TypeName::widest(lhs->type(), rhs->type());
            if (lhs->type() == rhs->type())
                return lhs->type();
            if (lhs->type() == TypeName::Auto && rhs->type() != TypeName::Auto)
                return rhs->type();
            if (rhs->type() == TypeName::Auto && lhs->type() != TypeName::Auto)
                return lhs->type();
            throw CompileError("Unable to resolve operator {0} between {1} and {2}",
                               opName().empty() ? rtti()->name() : opName(),
                               lhs->type(),
                               rhs->type());
        }

        std::string to_string() const override {
            auto str = node_name();
            if (lhs && rhs) {
                str += std::string(llvm::formatv("({0}), ({1})", lhs->to_string(), rhs->to_string()));
            }
            return str;
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) +
                   std::string(llvm::formatv("({0}, {1})", lhs ? lhs->dump() : "empty", rhs ? rhs->dump() : "empty"));
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(lhs);
            visitor.visit(rhs);
        }

        virtual std::string_view opName() const { return {}; }
    };

    struct Add : public BinaryOp {
        DECLARE_RTTI(Add, BinaryOp);
        SEMA_NODE_POD_CLONE(Add);

      public:
        using BinaryOp::BinaryOp;

        std::string_view opName() const override { return "+"; }
    };

    struct Sub : public BinaryOp {
        DECLARE_RTTI(Sub, BinaryOp);
        SEMA_NODE_POD_CLONE(Sub);

      public:
        using BinaryOp::BinaryOp;

        std::string_view opName() const override { return "-"; }
    };

    struct Mul : public BinaryOp {
        DECLARE_RTTI(Mul, BinaryOp);
        SEMA_NODE_POD_CLONE(Mul);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return "*"; }
    };

    struct Div : public BinaryOp {
        DECLARE_RTTI(Div, BinaryOp);
        SEMA_NODE_POD_CLONE(Div);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return "/"; }
    };

    struct Mod : public BinaryOp {
        DECLARE_RTTI(Mod, BinaryOp);
        SEMA_NODE_POD_CLONE(Mod);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return "%"; }
    };

    struct Pow : public BinaryOp {
        DECLARE_RTTI(Pow, BinaryOp);
        SEMA_NODE_POD_CLONE(Pow);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return "**"; }
    };

    // Special override of Equal that will not be replaced by operator overloads
    struct Identical : public BinaryOp {
        DECLARE_RTTI(Identical, BinaryOp);
        SEMA_NODE_POD_CLONE(Identical);

        const TypeName& type() const override {
            return TypeName::Bool;
        }

    public:
        using BinaryOp::BinaryOp;
    };

    struct Equal : public BinaryOp {
        DECLARE_RTTI(Equal, BinaryOp);
        SEMA_NODE_POD_CLONE(Equal);

        const TypeName& type() const override {
            return TypeName::Bool;
        }

      public:
        using BinaryOp::BinaryOp;

        std::string_view opName() const override { return "=="; }
    };

    struct NotEqual : public BinaryOp {
        DECLARE_RTTI(NotEqual, BinaryOp);
        SEMA_NODE_POD_CLONE(NotEqual);

        const TypeName& type() const override {
            return TypeName::Bool;
        }

      public:
        using BinaryOp::BinaryOp;

        std::string_view opName() const override { return "!="; }
    };

    struct Less : public BinaryOp {
        DECLARE_RTTI(Less, BinaryOp);
        SEMA_NODE_POD_CLONE(Less);

      public:
        using BinaryOp::BinaryOp;

        std::string_view opName() const override { return "<"; }
    };

    struct LessEqual : public BinaryOp {
        DECLARE_RTTI(LessEqual, BinaryOp);
        SEMA_NODE_POD_CLONE(LessEqual);

      public:
        using BinaryOp::BinaryOp;

        std::string_view opName() const override { return "<="; }
    };

    struct Greater : public BinaryOp {
        DECLARE_RTTI(Greater, BinaryOp);
        SEMA_NODE_POD_CLONE(Greater);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return ">"; }
    };

    struct GreaterEqual : public BinaryOp {
        DECLARE_RTTI(GreaterEqual, BinaryOp);
        SEMA_NODE_POD_CLONE(GreaterEqual);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return ">="; }
    };

    struct LShift : public BinaryOp {
        DECLARE_RTTI(LShift, BinaryOp);
        SEMA_NODE_POD_CLONE(LShift);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return "<<"; }
    };

    struct RShift : public BinaryOp {
        DECLARE_RTTI(RShift, BinaryOp);
        SEMA_NODE_POD_CLONE(RShift);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return ">>"; }
    };

    struct BitAnd : public BinaryOp {
        DECLARE_RTTI(BitAnd, BinaryOp);
        SEMA_NODE_POD_CLONE(BitAnd);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return "&"; }
    };

    struct BitOr : public BinaryOp {
        DECLARE_RTTI(BitOr, BinaryOp);
        SEMA_NODE_POD_CLONE(BitOr);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return "|"; }
    };

    struct BitXor : public BinaryOp {
        DECLARE_RTTI(BitXor, BinaryOp);
        SEMA_NODE_POD_CLONE(BitXor);

      public:
        using BinaryOp::BinaryOp;
        std::string_view opName() const override { return "^"; }
    };

    struct LogicalAnd : public BinaryOp {
        DECLARE_RTTI(LogicalAnd, BinaryOp);
        SEMA_NODE_POD_CLONE(LogicalAnd);

      public:
        using BinaryOp::BinaryOp;
    };

    struct LogicalOr : public BinaryOp {
        DECLARE_RTTI(LogicalOr, BinaryOp);
        SEMA_NODE_POD_CLONE(LogicalOr);

      public:
        using BinaryOp::BinaryOp;
    };

    struct Assign : public BinaryOp {
        DECLARE_RTTI(Assign, BinaryOp);
        SEMA_NODE_POD_CLONE(Assign);

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
        SEMA_NODE_POD_CLONE(AddAssign);

      public:
        using CompoundAssign::CompoundAssign;

        std::string_view opName() const override {
            return "+=";
        }
    };

    struct SubAssign : public CompoundAssign {
        DECLARE_RTTI(SubAssign, CompoundAssign);
        SEMA_NODE_POD_CLONE(SubAssign);

      public:
        using CompoundAssign::CompoundAssign;

        std::string_view opName() const override {
            return "-=";
        }
    };

    struct MulAssign : public CompoundAssign {
        DECLARE_RTTI(MulAssign, CompoundAssign);
        SEMA_NODE_POD_CLONE(MulAssign);

      public:
        using CompoundAssign::CompoundAssign;

        std::string_view opName() const override {
            return "*=";
        }
    };

    struct DivAssign : public CompoundAssign {
        DECLARE_RTTI(DivAssign, CompoundAssign);
        SEMA_NODE_POD_CLONE(DivAssign);

      public:
        using CompoundAssign::CompoundAssign;

        std::string_view opName() const override {
            return "/=";
        }
    };

    struct ModAssign : public CompoundAssign {
        DECLARE_RTTI(ModAssign, CompoundAssign);
        SEMA_NODE_POD_CLONE(ModAssign);

      public:
        using CompoundAssign::CompoundAssign;

        std::string_view opName() const override { return "%="; }
    };

    struct LShiftAssign : public CompoundAssign {
        DECLARE_RTTI(LShiftAssign, CompoundAssign);
        SEMA_NODE_POD_CLONE(LShiftAssign);

      public:
        using CompoundAssign::CompoundAssign;

        std::string_view opName() const override {
            return "<<="; }
    };

    struct RShiftAssign : public CompoundAssign {
        DECLARE_RTTI(RShiftAssign, CompoundAssign);
        SEMA_NODE_POD_CLONE(RShiftAssign);

      public:
        using CompoundAssign::CompoundAssign;

        std::string_view opName() const override {
            return ">>="; }
    };

    struct BitAndAssign : public CompoundAssign {
        DECLARE_RTTI(BitAndAssign, CompoundAssign);
        SEMA_NODE_POD_CLONE(BitAndAssign);

      public:
        using CompoundAssign::CompoundAssign;

        std::string_view opName() const override { return "&="; }
    };

    struct BitOrAssign : public CompoundAssign {
        DECLARE_RTTI(BitOrAssign, CompoundAssign);
        SEMA_NODE_POD_CLONE(BitOrAssign);

      public:
        using CompoundAssign::CompoundAssign;

        std::string_view opName() const override { return "|="; }
    };

    struct BitXorAssign : public CompoundAssign {
        DECLARE_RTTI(BitXorAssign, CompoundAssign);
        SEMA_NODE_POD_CLONE(BitXorAssign);

      public:
        using CompoundAssign::CompoundAssign;

        std::string_view opName() const override { return "^="; }
    };

    struct Index : public Expression {
        DECLARE_RTTI(Index, Expression);
        SEMA_NODE_POD_CLONE(Index);

        TNodeRef<Expression> lhs;
        TNodeRef<Expression> expr;

      public:
        Index(Expression* lhs = nullptr, Expression* indexExpr = nullptr)
            : lhs(lhs)
            , expr(indexExpr) {}

        const TypeName& type() const override {
            return lhs->type();
        }

        std::string to_string() const override {
            return llvm::formatv(
                "{0} {1}[{2}]", node_name(), lhs ? lhs->to_string() : "None", expr ? expr->to_string() : "??");
        }

        std::string dump(int indent) const override {
            return llvm::formatv(
                "{0} {1}[{2}]", Node::dump(indent), lhs ? lhs->dump() : "None", expr ? expr->dump() : "??");
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(lhs);
            visitor.visit(expr);
        }
    };
} // namespace pepper::sema
