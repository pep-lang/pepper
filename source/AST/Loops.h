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

        std::string dump() const override {
            return toString() + std::string(llvm::formatv("({0})", Condition->dump())) + Body->dump();
        }
    };

    class ForIndex : public Node {
        DECLARE_RTTI(ForIndex, Node);

        Ref<VariableDef> Init;
        Ref<Expression> Condition;
        Ref<Expression> Next;
        Ref<Block> Body;

        std::string toString() const override {
            return Node::toString();
        }

        std::string dump() const override {
            return Node::dump() +
                   std::string(llvm::formatv("({0}; {1}; {2})", Init->dump(), Condition->dump(), Next->dump())) +
                   Body->dump();
        }
    };

    class ForRange : public Node {
        DECLARE_RTTI(ForRange, Node);

        Ref<VariableDef> Var;
        Ref<Expression> Range;
        Ref<Block> Body;

        std::string toString() const override {
            return Node::toString();
        }

        std::string dump() const override {
            return Node::dump() + std::string(llvm::formatv("{0} : {1}", Var->dump(), Range->dump())) + Body->dump();
        }
    };
} // namespace pepper::ast
