//
// Created by Justin Boswell on 12/29/22.
//

#pragma once

#include <utility>

#include "AST/Node.h"
#include "Core/Query.h"
#include "Core/Vector.h"

namespace pepper::ast {
    struct Block : public Node {
        DECLARE_RTTI(Block, Node);

        std::string Name;
        NodeList<Node> Items;

        Block(std::string name = "block", NodeList<Node> body = {})
            : Name(std::move(name))
            , Items(std::move(body)) {}

        Block(const Block& block)
            : Block(block.Name) {
            Items.clone(block.Items);
        }

        Block(Block&&) = default;

        Block& operator=(const Block& block) {
            Name = block.Name;
            Items.clone(block.Items);
            return *this;
        };

        std::string toString() const override {
            static int indent = 0;

            std::string str = std::string(llvm::formatv("{0}: {1}", Node::toString(), Name));
            Vector<std::string> items = Query(Items).select<std::string>([](auto& item) { return item->toString(); });
            if (items.size()) {
                indent += 2;
                auto indentStr = repeat(" ", indent);
                std::string padding = std::string("\n") + indentStr;
                str = std::string(llvm::formatv("{0}: {{\n", Name)) + indentStr + llvm::join(items, padding) + "\n}";
                indent -= 2;
            }

            return str;
        }

        std::string dump(int indent) const override {
            Vector<std::string> items =
                Query(Items).select<std::string>([&indent](auto& item) { return item->dump(indent); });
            return llvm::join(items, "\n");
        }

        Node* clone() const override {
            auto block = new Block(Name);
            block->Items.clone(Items);
            return block;
        }

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            for (auto& node : Items) {
                visitor.visit(node);
            }
        }
    };
} // namespace pepper::ast
