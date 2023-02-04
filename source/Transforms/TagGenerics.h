
#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Transforms/Transform.h"

namespace pepper::ast {
    struct TagGenerics : public Transformer {
        DECLARE_RTTI(TagGenerics, Transformer);

        void run(Ref<AST> parseTree) override {
            llvm::StringSet<> functions;

            for (auto& fn : parseTree->functions()) {
                if (!functions.contains(fn->Name)) {
                    functions.insert(fn->Name);
                    continue;
                }
                // If this isn't the first time this function name has been seen, then
                // this is a specialization
                if (fn->Type.SubTypes.size() > 0) {
                    fn->Generic = false;
                    fn->Name = fn->Type.toString();
                    PEP_TRACE_AST("Specialization: {0}", fn->Name);
                }
            }
        }
    };
} // namespace pepper::ast
