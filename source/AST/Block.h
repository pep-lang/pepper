//
// Created by Justin Boswell on 12/29/22.
//

#pragma once

#include "AST/Node.h"
#include "Core/Query.h"
#include "Core/Vector.h"

namespace pepper::ast {
    struct Block : public Node {
        DECLARE_RTTI(Block, Node);

        std::string Name;
        Vector<Ref<Node>> Items;

        Block(const std::string& name = "block")
            : Name(name) {
        }

        Block(const Block& block)
            : Name(block.Name) {
            for (const auto& node : block.Items) {
                Items.emplace_back(node->clone());
            }
        }

        Block(Block&&) = default;
        Block& operator=(const Block&) = default;

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
            indent += 2;
            Vector<std::string> items =
                Query(Items).select<std::string>([&indent](auto& item) { return item->dump(indent); });
            std::string str = std::string(llvm::formatv("{0}: {{\n", Name)) + llvm::join(items, "\n") + "\n}";
            indent -= 2;
            return str;
        }

        Ref<Node> clone() const override {
            auto block = Ref<Block>::New(Name);
            for (const auto& node : Items) {
                auto clone = node->clone();
                block->Items.emplace_back(clone);
            }
            return block;
        }

        void specialize(const Specialization& spec) override {
            for (auto& node : Items) {
                node->specialize(spec);
            }
        }
    };
} // namespace pepper::ast
