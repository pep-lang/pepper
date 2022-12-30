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

    class If : public Branch {
        DECLARE_RTTI(If, Branch);

      public:
        std::string toString() const override {
            return Node::toString();
        }

        std::string dump() const override {
            auto ifCond = std::string(llvm::formatv("if ({0}) {{\n", Condition ? Condition->dump() : "??"));
            auto thenBlock = Then ? Then->dump() + "}" : "";
            auto elseBlock = Else ? std::string(" else {\n  ") + Else->dump() + "}" : "";
            return ifCond + thenBlock + elseBlock + "\n";
        }
    };

    class Ternary : public Expression {
        DECLARE_RTTI(Ternary, Expression);

        Ref<Expression> Condition;
        Ref<Expression> TrueResult;
        Ref<Expression> FalseResult;

      public:
        std::string toString() const override {
            return Node::toString();
        }

        std::string dump() const override {
            return std::string(
                llvm::formatv("({0}) ? {1} : {2}", Condition->dump(), TrueResult->dump(), FalseResult->dump()));
        }
    };
} // namespace pepper::ast
