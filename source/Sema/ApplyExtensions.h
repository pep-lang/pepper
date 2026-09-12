#pragma once

#include <cassert>

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"
#include "Sema/Specialization.h"
#include "Sema/Transform.h"

namespace pepper::sema {
    struct ApplyExtensions : public Transformer {
        DECLARE_RTTI(ApplyExtensions, Transformer);

        SymbolTable symbols;
        bool report_missing = true;

        // Track which extensions have been applied. Application happens in 2 passes:
        // Once before specializations for concrete/generic extensions, and then again after specialization
        // for specialized struct extensions
        static llvm::DenseSet<ExtensionDef*>& applied() {
            static llvm::DenseSet<ExtensionDef*> Applied;
            return Applied;
        }

        ApplyExtensions(bool reportMissing)
            : report_missing(reportMissing) {}

        void run(Ref<Module> module) override {
            symbols = SymbolTable(*module);

            for (const auto& ext : module->extensions()) {
                if (applied().contains(ext))
                    continue;

                if (!ext->Target.value()) {
                    if (report_missing)
                        throw CompileError("Cannot extend non-existent struct {0}", ext->Target.name());
                    continue;
                }

                applied().insert(ext);
                auto target = ext->Target.value();
                for (const auto& srcMethod : ext->method_members) {
                    PEP_TRACE_AST("Method: {0}.{1}", target->name, srcMethod->name);
                    auto method = srcMethod->clone_as<MethodDef>();
                    method->parent = target;
                    target->method_members.push_back(method);
                }
                if (auto trait = ext->as<TraitDef>()) {
                    target->traits.emplace_back(trait);
                }
            }
        }
    };
} // namespace pepper::sema
