
#pragma once

#include "AST/Block.h"
#include "AST/Visitor.h"
#include "Core/Query.h"
#include "Core/String.h"
#include "Core/Vector.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper::ast {

    // Branches can be expressions (ternary/loops) or void (if/else)
    struct Branch : public Expression {
        DECLARE_RTTI(Branch, Expression);

        TNodeRef<Expression> Condition;
        TNodeRef<Block> Then;
        TNodeRef<Block> Else;

        Branch(Expression* condition = nullptr, Block* thenBlock = nullptr, Block* elseBlock = nullptr)
            : Condition(condition)
            , Then(thenBlock)
            , Else(elseBlock) {}

        Branch(const Branch& br)
            : Condition(br.Condition->cloneAs<Expression>())
            , Then(br.Then->cloneAs<Block>())
            , Else(br.Else ? br.Else->cloneAs<Block>() : nullptr) {}

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(Condition);
            visitor.visit(Then);
            if (Else) {
                visitor.visit(Else);
            }
        }
    };

    struct If : public Branch {
        DECLARE_RTTI(If, Branch);
        AST_NODE_POD_CLONE(If);

        using Branch::Branch;

        std::string toString() const override {
            return nodeName();
        }

        std::string dump(int indent) const override {
            auto indentStr = repeat(" ", indent);
            auto ifCond = std::string(llvm::formatv("if ({0}) {{\n", Condition ? Condition->dump() : "??"));
            auto thenBlock = Then ? Then->dump(indent + 2) : "";
            auto elseBlock = Else ? std::string(" else {\n") + Else->dump(indent + 2) + "\n" + indentStr + "}" : "";
            return indentStr + ifCond + thenBlock + "\n" + indentStr + "}" + elseBlock;
        }
    };

    struct Ternary : public Expression {
        DECLARE_RTTI(Ternary, Expression);
        AST_NODE_POD_CLONE(Ternary);

        TNodeRef<Expression> Condition;
        TNodeRef<Expression> TrueResult;
        TNodeRef<Expression> FalseResult;

        Ternary() = default;

        Ternary(const Ternary& t)
            : Condition(t.Condition->cloneAs<Expression>())
            , TrueResult(t.TrueResult->cloneAs<Expression>())
            , FalseResult(t.FalseResult->cloneAs<Expression>()) {}

        const TypeName& type() const override {
            return TrueResult->type();
        }

        std::string toString() const override {
            return nodeName();
        }

        std::string dump(int) const override {
            return std::string(
                llvm::formatv("({0}) ? {1} : {2}", Condition->dump(), TrueResult->dump(), FalseResult->dump()));
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(Condition);
            visitor.visit(TrueResult);
            visitor.visit(FalseResult);
        }
    };
} // namespace pepper::ast
