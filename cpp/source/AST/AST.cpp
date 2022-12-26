
#include "AST/AST.h"
#include "AST/Node.h"

#include <iostream>

namespace pepper::ast {

    AST::AST() {
    }

    void AST::newRoot(Ref<Node> root) {
        Roots.push_back(root);
    }


    void AST::dump() const {
        for (const auto& root : Roots) {
            std::cout << root->toString() << std::endl;
        }
    }
} // namespace pepper::ast
