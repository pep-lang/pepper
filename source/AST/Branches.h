//
// Created by justi on 12/27/2022.
//

#pragma once

#include "AST/Node.h"
#include "Core/Query.h"
#include "Core/String.h"
#include "Core/Vector.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper::ast {
    class Block : public Node {
        DECLARE_RTTI(Block, Node);

        const std::string Name;
        Ref<Node> Parent;
        Vector<Ref<Node>> Items;

      public:
        Block(Ref<Node> parent = nullptr, const std::string& name = "block")
            : Parent(parent)
            , Name(name) {
        }

        const std::string& name() const {
            return Name;
        }

        Vector<Ref<Node>>& items() {
            return Items;
        }

        Ref<Node> parent() {
            return Parent;
        }

        std::string toString() const override {
            static int indent = 0;

            std::string str = std::string(llvm::formatv("{0}: {1}", Node::toString(), Name));
            Vector<std::string> items = Query(Items).select<std::string>([](auto item) { return item->toString(); });
            if (items.size()) {
                indent += 2;
                std::string padding = std::string("\n") + repeat(" ", indent);
                str = std::string(llvm::formatv("{0}: {{\n", Name)) + llvm::join(items, padding) + "\n}";
                indent -= 2;
            }

            return str;
        }

        std::string dump() const override {
            static int indent = 0;
            indent += 2;
            Vector<std::string> items = Query(Items).select<std::string>([](auto item) { return item->dump(); });
            std::string padding = std::string("\n") + repeat(" ", indent);
            std::string str = std::string(llvm::formatv("{0}: {{\n", Name)) + llvm::join(items, padding) + "\n}";
            indent -= 2;
            return str;
        }
    };

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
            return std::string(llvm::formatv("({0}) ? {1} : {2}", Condition->dump(), TrueResult->dump(), FalseResult->dump()));
        }
    };
} // namespace pepper::ast
