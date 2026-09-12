
#pragma once

#include "Sema/Model/Block.h"
#include "Sema/Model/Visitor.h"
#include "Core/Query.h"
#include "Core/String.h"
#include "Core/Vector.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper::sema {

    // Branches can be expressions (ternary/loops) or void (if/else)
    struct Branch : public Expression {
        DECLARE_RTTI(Branch, Expression);

        TNodeRef<Expression> condition;
        TNodeRef<Block> then_block;
        TNodeRef<Block> else_block;

        Branch(Expression* condition = nullptr, Block* thenBlock = nullptr, Block* elseBlock = nullptr)
            : condition(condition)
            , then_block(thenBlock)
            , else_block(elseBlock) {}

        Branch(const Branch& br)
            : condition(br.condition->clone_as<Expression>())
            , then_block(br.then_block->clone_as<Block>())
            , else_block(br.else_block ? br.else_block->clone_as<Block>() : nullptr) {}

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(condition);
            visitor.visit(then_block);
            if (else_block) {
                visitor.visit(else_block);
            }
        }
    };

    struct If : public Branch {
        DECLARE_RTTI(If, Branch);
        SEMA_NODE_POD_CLONE(If);

        using Branch::Branch;

        std::string to_string() const override {
            return node_name();
        }

        std::string dump(int indent) const override {
            auto indentStr = repeat(" ", indent);
            auto ifCond = std::string(llvm::formatv("if ({0}) {{\n", condition ? condition->dump() : "??"));
            auto thenBlock = then_block ? then_block->dump(indent + 2) : "";
            auto elseBlock =
                else_block ? std::string(" else {\n") + else_block->dump(indent + 2) + "\n" + indentStr + "}" : "";
            return indentStr + ifCond + thenBlock + "\n" + indentStr + "}" + elseBlock;
        }
    };

    struct Ternary : public Expression {
        DECLARE_RTTI(Ternary, Expression);
        SEMA_NODE_POD_CLONE(Ternary);

        TNodeRef<Expression> condition;
        TNodeRef<Expression> true_expr;
        TNodeRef<Expression> false_expr;

        Ternary() = default;

        Ternary(Expression* cond, Expression* t, Expression* f)
            : condition(cond)
            , true_expr(t)
            , false_expr(f) {}

        Ternary(const Ternary& t)
            : condition(t.condition->clone_as<Expression>())
            , true_expr(t.true_expr->clone_as<Expression>())
            , false_expr(t.false_expr->clone_as<Expression>()) {}

        const TypeName& type() const override {
            return true_expr->type();
        }

        std::string to_string() const override {
            return node_name();
        }

        std::string dump(int) const override {
            return std::string(
                llvm::formatv("({0}) ? {1} : {2}", condition->dump(), true_expr->dump(), false_expr->dump()));
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(condition);
            visitor.visit(true_expr);
            visitor.visit(false_expr);
        }
    };
} // namespace pepper::sema
