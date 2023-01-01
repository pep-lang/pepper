//
// Created by Justin Boswell on 12/29/22.
//

#pragma once

#include "AST/Block.h"
#include "AST/Variables.h"

namespace pepper::ast {
    class While : public Node {
        DECLARE_RTTI(While, Node);

        Ref<Expression> Condition;
        Ref<Block> Body;

        std::string toString() const override {
            return Node::toString();
        }

        std::string dump(int indent = 0) const override {
            return Node::dump(indent) + std::string(llvm::formatv("({0})", Condition->toString())) + Body->dump(indent);
        }
    };

    class ForRange : public Node {
        DECLARE_RTTI(ForRange, Node);

        Ref<VariableDef> Var;
        Ref<Expression> Init;
        Ref<Expression> Step;
        Ref<Expression> Done;
        Ref<Block> Body;

        std::string toString() const override {
            return Node::toString();
        }

        std::string dump(int indent = 0) const override {
            return Node::dump(indent) +
                   std::string(llvm::formatv(
                       "{0} : {1}..{2}", Var ? Var->toString() : "", Init->toString(), Done->toString())) +
                   Body->dump(indent);
        }
    };
} // namespace pepper::ast
