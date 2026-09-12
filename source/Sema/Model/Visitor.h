
#pragma once

#include "Sema/Model/Node.h"
#include "llvm/ADT/DenseSet.h"

namespace pepper::sema {
    class ResolvableBase;

    template <typename T>
    class Resolvable;

    class Visitor {
        llvm::DenseSet<Node*> visited;
        Vector<class Block*> stack;

      protected:
        Block* block() const {
            return !stack.empty() ? stack.back() : nullptr;
        }

      protected:
        virtual void visitType(struct TypeName& type) {}

        virtual void visitResolvable(ResolvableBase& res) {}

        virtual void enterNode(NodeRef& node) {}

        virtual void visitNode(NodeRef& node) {}

        virtual void exitNode(NodeRef& node) {}

      public:
        Visitor() = default;
        virtual ~Visitor() = default;

        void visit(struct TypeName& type);

        void visit(NodeRef& ref);

        void visit(Node* node);

        template <typename T>
        void visit(Resolvable<T>& target);
    };
} // namespace pepper::sema
