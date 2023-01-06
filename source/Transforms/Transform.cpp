//
// Created by Justin Boswell on 1/5/23.
//

#include "Transforms/Transform.h"

#include "Transforms/ReleaseFieldRefs.h"

namespace pepper::ast {
    TransformPass::TransformPass(Ref<AST> parseTree)
        : ParseTree(parseTree) {
        Transformers.emplace_back(new ReleaseFieldRefs());
    }

    Ref<AST> TransformPass::run() const {
        for (auto& xform : Transformers) {
            xform->run(ParseTree);
        }
        return ParseTree;
    }
} // namespace pepper::ast
