//
// Created by Justin Boswell on 12/29/22.
//

#pragma once

#include "AST/Node.h"
#include "Core/Query.h"
#include "Core/Vector.h"

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
                Query(Items).select<std::string>([&indent](auto item) { return item->dump(indent); });
            std::string str = std::string(llvm::formatv("{0}:\n", Name)) + llvm::join(items, "\n") + "\n}";
            indent -= 2;
            return str;
        }
    };
} // namespace pepper::ast
