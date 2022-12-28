//
// Created by justi on 12/27/2022.
//

#pragma once

#include "AST/Node.h"
#include "Core/Vector.h"

namespace pepper::ast {
    class Block : public Node {
        DECLARE_RTTI(Block, Node);

        const std::string Name;
        Ref<Node> Parent;
        Vector<Ref<Expression>> Items;

      public:
        Block(Ref<Node> parent = nullptr, const std::string& name = "block")
            : Parent(parent)
            , Name(name) {
        }

        const std::string& name() const {
            return Name;
        }

        Vector<Ref<Expression>> items() {
            return Items;
        }

        Ref<Node> parent() {
            return Parent;
        }
    };

    class Branch : public Expression {
        DECLARE_RTTI(Branch, Expression);

        Ref<Expression> Condition;
        Ref<Block> Then;
        Ref<Block> Else;

      public:
        Branch() = default;

        Ref<Expression>& condition() {
            return Condition;
        }

        Ref<Block>& thenBlock() {
            return Then;
        }

        Ref<Block>& elseBlock() {
            return Else;
        }
    };
} // namespace pepper::ast
