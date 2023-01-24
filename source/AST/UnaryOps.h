//
// Created by justi on 1/6/2023.
//

#pragma once

#include "AST/Node.h"

namespace pepper::ast {
    struct UnaryOp : public Expression {
        DECLARE_RTTI(UnaryOp, Expression);

        TNodeRef<Expression> Operand;

        UnaryOp(Expression* operand)
            : Operand(operand) {}

        UnaryOp(const UnaryOp& op)
            : Expression(op)
            , Operand(op.Operand->cloneAs<Expression>()) {}

        const TypeName& type() const override {
            return Operand->type();
        }

        std::string toString() const override {
            auto str = Node::toString();
            if (Operand) {
                str += std::string(llvm::formatv("({0})", Operand->toString()));
            }
            return str;
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) + std::string(llvm::formatv("({0})", Operand ? Operand->dump() : "empty"));
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(Operand);
        }
    };

    struct Minus : public UnaryOp {
        DECLARE_RTTI(Minus, UnaryOp);
        AST_NODE_POD_CLONE(Minus);

      public:
        using UnaryOp::UnaryOp;
    };

    struct Plus : public UnaryOp {
        DECLARE_RTTI(Plus, UnaryOp);
        AST_NODE_POD_CLONE(Plus);

      public:
        using UnaryOp::UnaryOp;
    };

    struct PreIncrement : public UnaryOp {
        DECLARE_RTTI(PreIncrement, UnaryOp);
        AST_NODE_POD_CLONE(PreIncrement);

      public:
        using UnaryOp::UnaryOp;
    };

    struct PostIncrement : public UnaryOp {
        DECLARE_RTTI(PostIncrement, UnaryOp);
        AST_NODE_POD_CLONE(PostIncrement);

      public:
        using UnaryOp::UnaryOp;
    };

    struct PreDecrement : public UnaryOp {
        DECLARE_RTTI(PreDecrement, UnaryOp);
        AST_NODE_POD_CLONE(PreDecrement);

      public:
        using UnaryOp::UnaryOp;
    };

    struct PostDecrement : public UnaryOp {
        DECLARE_RTTI(PostDecrement, UnaryOp);
        AST_NODE_POD_CLONE(PostDecrement);

      public:
        using UnaryOp::UnaryOp;
    };

    struct LogicalNot : public UnaryOp {
        DECLARE_RTTI(LogicalNot, UnaryOp);
        AST_NODE_POD_CLONE(LogicalNot);

      public:
        using UnaryOp::UnaryOp;
    };

    struct BitNot : public UnaryOp {
        DECLARE_RTTI(BitNot, UnaryOp);
        AST_NODE_POD_CLONE(BitNot);

      public:
        using UnaryOp::UnaryOp;
    };
} // namespace pepper::ast
