
#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Sema/Transform.h"

namespace pepper::sema {
    struct TagGenerics : public Transformer {
        DECLARE_RTTI(TagGenerics, Transformer);

        void run(Ref<Module> module) override {
            llvm::StringSet<> functions;

            for (auto& fn : module->functions()) {
                if (!functions.contains(fn->name)) {
                    functions.insert(fn->name);
                    continue;
                }
                // If this isn't the first time this function name has been seen, then
                // this is a specialization
                if (fn->type.sub_types.size() > 0) {
                    fn->is_generic_func = false;
                    fn->name = fn->type.to_string();
                    PEP_TRACE_AST("Specialization: {0}", fn->name);
                }
            }
        }
    };
} // namespace pepper::sema
