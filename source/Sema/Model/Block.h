
#pragma once

#include <utility>

#include "Sema/Model/Node.h"
#include "Sema/Model/Visitor.h"
#include "Core/Query.h"
#include "Core/Vector.h"

namespace pepper::sema {
    struct Block : public Node {
        DECLARE_RTTI(Block, Node);

        std::string name;
        NodeList<Node> items;

        Block(std::string name = "block", NodeList<Node> body = {})
            : name(std::move(name))
            , items(std::move(body)) {}

        Block(const Block& block)
            : Block(block.name) {
            items.clone(block.items);
        }

        Block(Block&&) = default;

        Block& operator=(const Block& block) {
            name = block.name;
            items.clone(block.items);
            return *this;
        };

        std::string to_string() const override {
            static int indent = 0;

            std::string str = std::string(llvm::formatv("{0}: {1}", node_name(), name));
            Vector<std::string> items_str = Query(items).select<std::string>([](auto& item) { return item->to_string(); });
            if (items_str.size()) {
                indent += 2;
                auto indentStr = repeat(" ", indent);
                std::string padding = std::string("\n") + indentStr;
                str = std::string(llvm::formatv("{0}: {{\n", name)) + indentStr + llvm::join(items_str, padding) + "\n}";
                indent -= 2;
            }

            return str;
        }

        std::string dump(int indent) const override {
            Vector<std::string> items_str =
                Query(items).select<std::string>([&indent](auto& item) { return item->dump(indent); });
            return llvm::join(items_str, "\n");
        }

        Node* clone() const override {
            auto block = new Block(name);
            block->items.clone(items);
            return block;
        }

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            // It is possible for the body list to be modified during traversal,
            // so the position in iteration must be maintained without an invalidating iterator
            for (size_t idx = 0; idx < items.size(); ++idx) {
                auto& node = items[idx];
                visitor.visit(node);
            }
        }
    };
} // namespace pepper::sema
