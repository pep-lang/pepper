
#include "AST/AST.h"

namespace pepper::ast {

    AST::AST() {
    }

    void AST::newRoot(Ref<Node> root) {
        Roots.push_back(root);
    }

} // namespace pepper::ast
