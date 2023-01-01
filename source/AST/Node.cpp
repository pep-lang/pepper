//
// Created by Justin Boswell on 1/1/23.
//

#include "AST/Node.h"

namespace pepper::ast {
    std::string Node::sourcePrefix(int width, int indent) const {
        width = (width >= 0) ? width : Source.File.size() + 10;
        width += indent;
        std::string src = Source.toString();
        std::string padding = repeat(" ", width - src.size());
        return llvm::formatv("{0}:{1}", Source.toString(), padding);
    }

    std::string Node::toString() const {
        return llvm::formatv("{0}: ", rtti()->name());
    }

    std::string Node::dump(int indent) const {
        return llvm::formatv("{0}{1} ", repeat(" ", indent), rtti()->name());
    }
} // namespace pepper::ast
