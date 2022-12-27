
#include "AST/AST.h"
#include <iostream>

#include "AST/Node.h"
#include "Core/Messages.h"

namespace pepper::ast {

    AST::AST() {
    }

    void AST::newRoot(Ref<Node> root) {
        Roots.push_back(root);
    }

    void AST::dump() const {
        if (PEP_TRACING(TraceChannel::AST)) {
            for (const auto& root : Roots) {
                PEP_TRACE_AST(root->toString());
            }
        }
    }
} // namespace pepper::ast
