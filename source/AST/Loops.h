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

        Ref<Expression> Condition;
        Ref<Block> Body;

        std::string toString() const override {
            return Node::toString();
        }

        std::string dump(int indent = 0) const override {
            return Node::dump(indent) + std::string(llvm::formatv("({0})", Condition->toString())) + Body->dump(indent);
        }

        void specialize(const Specialization& spec) override {
            Condition->specialize(spec);
            Body->specialize(spec);
        }
    };

    struct ForRange : public Node {
        DECLARE_RTTI(ForRange, Node);
        AST_NODE_POD_CLONE(ForRange);

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

        void specialize(const Specialization& spec) override {
            Var->specialize(spec);
            Init->specialize(spec);
            Step->specialize(spec);
            Done->specialize(spec);
            Body->specialize(spec);
        }
    };
} // namespace pepper::ast
