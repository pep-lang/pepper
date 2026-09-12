
#pragma once

#include "Sema/Model/Node.h"

namespace pepper::sema {
    struct UnaryOp : public Expression {
        DECLARE_RTTI(UnaryOp, Expression);

        TNodeRef<Expression> operand;

        UnaryOp(Expression* operand)
            : operand(operand) {}

        UnaryOp(const UnaryOp& op)
            : Expression(op)
            , operand(op.operand->clone_as<Expression>()) {}

        const TypeName& type() const override {
            return operand->type();
        }

        std::string to_string() const override {
            auto str = node_name();
            if (operand) {
                str += std::string(llvm::formatv("({0})", operand->to_string()));
            }
            return str;
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) + std::string(llvm::formatv("({0})", operand ? operand->dump() : "empty"));
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(operand);
        }
    };

    struct Minus : public UnaryOp {
        DECLARE_RTTI(Minus, UnaryOp);
        SEMA_NODE_POD_CLONE(Minus);

      public:
        using UnaryOp::UnaryOp;
    };

    struct Plus : public UnaryOp {
        DECLARE_RTTI(Plus, UnaryOp);
        SEMA_NODE_POD_CLONE(Plus);

      public:
        using UnaryOp::UnaryOp;
    };

    struct PreIncrement : public UnaryOp {
        DECLARE_RTTI(PreIncrement, UnaryOp);
        SEMA_NODE_POD_CLONE(PreIncrement);

      public:
        using UnaryOp::UnaryOp;
    };

    struct PostIncrement : public UnaryOp {
        DECLARE_RTTI(PostIncrement, UnaryOp);
        SEMA_NODE_POD_CLONE(PostIncrement);

      public:
        using UnaryOp::UnaryOp;
    };

    struct PreDecrement : public UnaryOp {
        DECLARE_RTTI(PreDecrement, UnaryOp);
        SEMA_NODE_POD_CLONE(PreDecrement);

      public:
        using UnaryOp::UnaryOp;
    };

    struct PostDecrement : public UnaryOp {
        DECLARE_RTTI(PostDecrement, UnaryOp);
        SEMA_NODE_POD_CLONE(PostDecrement);

      public:
        using UnaryOp::UnaryOp;
    };

    struct LogicalNot : public UnaryOp {
        DECLARE_RTTI(LogicalNot, UnaryOp);
        SEMA_NODE_POD_CLONE(LogicalNot);

      public:
        using UnaryOp::UnaryOp;
    };

    struct BitNot : public UnaryOp {
        DECLARE_RTTI(BitNot, UnaryOp);
        SEMA_NODE_POD_CLONE(BitNot);

      public:
        using UnaryOp::UnaryOp;
    };
} // namespace pepper::sema
