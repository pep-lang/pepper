//
// Created by Justin Boswell on 1/5/23.
//

#pragma once

#include <memory>

#include "AST/AST.h"

namespace pepper::ast {
    struct Transformer {
        virtual void run(Ref<AST> parseTree) = 0;
    };

    class TransformPass {
        Ref<AST> ParseTree;
        Vector<std::unique_ptr<Transformer>> Transformers;

      public:
        TransformPass(Ref<AST> parseTree);

        Ref<AST> run() const;
    };
} // namespace pepper::ast
