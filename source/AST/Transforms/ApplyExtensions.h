#pragma once

#include <cassert>

#include "AST/Nodes.h"
#include "AST/Transforms/Specialization.h"
#include "AST/Transforms/Transform.h"
#include "Core/Exceptions.h"
#include "Core/Messages.h"

namespace pepper::ast {
    struct ApplyExtensions : public Transformer {
        DECLARE_RTTI(ApplyExtensions, Transformer);

        SymbolTable Symbols;
        bool ReportMissing = true;

        // Track which extensions have been applied. Application happens in 2 passes:
        // Once before specializations for concrete/generic extensions, and then again after specialization
        // for specialized struct extensions
        static llvm::DenseSet<ExtensionDef*>& applied() {
            static llvm::DenseSet<ExtensionDef*> Applied;
            return Applied;
        }

        ApplyExtensions(bool reportMissing)
            : ReportMissing(reportMissing) {}

        void run(Ref<AST> parseTree) override {
            Symbols = SymbolTable(*parseTree);

            for (const auto& ext : parseTree->extensions()) {
                if (applied().contains(ext))
                    continue;

                if (!ext->Target.value()) {
                    if (ReportMissing)
                        throw CompileError("Cannot extend non-existent struct {0}", ext->Target.name());
                    continue;
                }

                applied().insert(ext);
                auto target = ext->Target.value();
                for (const auto& srcMethod : ext->Methods) {
                    PEP_TRACE_AST("Method: {0}.{1}", target->Name, srcMethod->Name);
                    auto method = srcMethod->cloneAs<MethodDef>();
                    method->Struct = target;
                    target->Methods.push_back(method);
                }
                if (auto trait = ext->as<TraitDef>()) {
                    target->Traits.emplace_back(trait);
                }
            }
        }
    };
} // namespace pepper::ast
