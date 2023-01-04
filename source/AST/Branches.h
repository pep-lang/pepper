//
// Created by justi on 12/27/2022.
//

#pragma once

#include "AST/Block.h"
#include "Core/Query.h"
#include "Core/String.h"
#include "Core/Vector.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper::ast {

    // Branches can be expressions (ternary/loops) or void (if/else)
    struct Branch : public Expression {
        DECLARE_RTTI(Branch, Expression);

        Ref<Expression> Condition;
        Ref<Block> Then;
        Ref<Block> Else;

        Branch(Ref<Expression> condition = {}, Ref<Block> thenBlock = {}, Ref<Block> elseBlock = {})
            : Condition(condition)
            , Then(thenBlock)
            , Else(elseBlock) {
        }
    };

    struct If : public Branch {
        DECLARE_RTTI(If, Branch);
        AST_NODE_POD_CLONE(If);

        using Branch::Branch;

        std::string toString() const override {
            return Node::toString();
        }

        std::string dump(int indent) const override {
            auto ifCond = std::string(llvm::formatv("if ({0}) {{\n", Condition ? Condition->dump() : "??"));
            auto thenBlock = Then ? Then->dump(indent) + "}" : "";
            auto elseBlock = Else ? std::string(" else {\n  ") + Else->dump(indent) + "}" : "";
            return ifCond + thenBlock + elseBlock + "\n";
        }
    };

    struct Ternary : public Expression {
        DECLARE_RTTI(Ternary, Expression);
        AST_NODE_POD_CLONE(Ternary);

        Ref<Expression> Condition;
        Ref<Expression> TrueResult;
        Ref<Expression> FalseResult;

        std::string toString() const override {
            return Node::toString();
        }

        std::string dump(int indent) const override {
            return std::string(llvm::formatv(
                "({0}) ? {1} : {2}", Condition->toString(), TrueResult->toString(), FalseResult->toString()));
        }
    };
} // namespace pepper::ast
