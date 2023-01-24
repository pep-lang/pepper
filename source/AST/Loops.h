//
// Created by Justin Boswell on 12/29/22.
//

#pragma once

#include "AST/Block.h"
#include "AST/Variables.h"

namespace pepper::ast {
    struct While : public Node {
        DECLARE_RTTI(While, Node);
        AST_NODE_POD_CLONE(While);

        TNodeRef<Expression> Condition;
        TNodeRef<Block> Body;

        While() = default;

        std::string toString() const override {
            return Node::toString();
        }

        std::string dump(int indent = 0) const override {
            return Node::dump(indent) + std::string(llvm::formatv(" ({0}) {{\n", Condition->dump())) +
                   Body->dump(indent + 2) + "\n" + repeat(" ", indent) + "}";
        }

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            visitor.visit(Condition);
            visitor.visit(Body);
        }
    };

    struct ForRange : public Node {
        DECLARE_RTTI(ForRange, Node);
        AST_NODE_POD_CLONE(ForRange);

        TNodeRef<VariableDef> Var;
        TNodeRef<Expression> Init;
        TNodeRef<Expression> Step;
        TNodeRef<Expression> Done;
        TNodeRef<Block> Body;

        std::string toString() const override {
            return Node::toString();
        }

        std::string dump(int indent = 0) const override {
            return Node::dump(indent) +
                   std::string(llvm::formatv(
                       "{0} : {1}..{2}", Var ? Var->toString() : "", Init->toString(), Done->toString())) +
                   Body->dump(indent);
        }

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            visitor.visit(Var);
            visitor.visit(Init);
            visitor.visit(Step);
            visitor.visit(Done);
            visitor.visit(Body);
        }
    };
} // namespace pepper::ast
