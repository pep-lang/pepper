
#pragma once

#include "AST/Node.h"
#include "llvm/ADT/DenseSet.h"

namespace pepper::ast {
    template <typename T>
    class Resolvable;

    class Visitor {
        llvm::DenseSet<Node*> Visited;

      protected:
        virtual void visitType(struct TypeName& type) {}

        virtual void enterNode(NodeRef& node) {}

        virtual void visitNode(NodeRef& node) {}

        virtual void exitNode(NodeRef& node) {}

      public:
        void visit(struct TypeName& type);

        void visit(NodeRef& ref);

        void visit(Node* node);

        template <typename T>
        void visit(Resolvable<T>& target);
    };
} // namespace pepper::ast
