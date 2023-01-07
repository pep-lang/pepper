//
// Created by justi on 1/6/2023.
//

#pragma once

#include "AST/Node.h"

namespace pepper::ast {
    struct UnaryOp : public Expression {
        DECLARE_RTTI(UnaryOp, Expression);

        Ref<Expression> Operand;

        UnaryOp(Ref<Expression> operand)
            : Operand(operand) {
        }

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
} // namespace pepper::ast
