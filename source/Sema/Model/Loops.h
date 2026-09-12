

#pragma once

#include "Sema/Model/Block.h"
#include "Sema/Model/Variables.h"

namespace pepper::sema {
    struct While : public Node {
        DECLARE_RTTI(While, Node);
        SEMA_NODE_POD_CLONE(While);

        TNodeRef<Expression> condition;
        TNodeRef<Block> body;

        While() = default;

        While(Expression* cond, Block* block)
            : condition(cond)
            , body(block) {}

        std::string dump(int indent = 0) const override {
            return Node::dump(indent) + std::string(llvm::formatv(" ({0}) {{\n", condition->dump())) +
                   body->dump(indent + 2) + "\n" + repeat(" ", indent) + "}";
        }

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            visitor.visit(condition);
            visitor.visit(body);
        }
    };

    struct ForRange : public Node {
        DECLARE_RTTI(ForRange, Node);
        SEMA_NODE_POD_CLONE(ForRange);

        TNodeRef<VariableDef> iterator;
        TNodeRef<Expression> init;
        TNodeRef<Expression> step;
        TNodeRef<Expression> done;
        TNodeRef<Block> body;

        std::string dump(int indent = 0) const override {
            return Node::dump(indent) +
                   std::string(llvm::formatv(
                       "{0} : {1}..{2}", iterator ? iterator->to_string() : "", init->to_string(), done->to_string())) +
                   body->dump(indent);
        }

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            visitor.visit(iterator);
            visitor.visit(init);
            visitor.visit(step);
            visitor.visit(done);
            visitor.visit(body);
        }
    };
} // namespace pepper::sema
