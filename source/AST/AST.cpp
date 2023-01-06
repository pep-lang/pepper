
#include "AST/AST.h"

#include "AST/Builder.h"
#include "AST/Node.h"
#include "AST/Struct.h"
#include "Core/Messages.h"

namespace pepper::ast {

    AST::AST() {
    }

    void AST::newRoot(Ref<Node> root) {
        // sort structures ahead of functions, includes generic specializations
        if (root->is<StructDef>()) {
            int idx = 0;
            for (; idx < Roots.size(); ++idx) {
                if (!Roots[idx]->is<StructDef>())
                    break;
            }
            Roots.insert(Roots.begin() + idx, root);
        } else {
            Roots.push_back(root);
        }
    }

    void AST::dump() const {
        if (PEP_TRACING(TraceChannel::AST)) {
            for (const auto& root : Roots) {
                PEP_TRACE_AST(root->dump());
                PEP_TRACE_AST({}); // add a newline between roots
            }
        }
    }
} // namespace pepper::ast
