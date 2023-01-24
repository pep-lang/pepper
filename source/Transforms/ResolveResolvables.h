#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Transforms/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ResolveResolvables : public Transformer {
        DECLARE_RTTI(ResolveResolvables, Transformer);

        SymbolTable Symbols;
        const bool ReportMissing = true;

        ResolveResolvables(bool reportMissing)
            : ReportMissing(reportMissing) {}

        void run(Ref<AST> parseTree) override {
            Symbols = SymbolTable(*parseTree);

            for (auto& resolvable : Resolvable<StructDef>::Instances()) {
                if (!resolvable->value()) {
                    if (auto st = Symbols.Structs.lookup(resolvable->name())) {
                        resolvable->resolve(st);
                        continue;
                    }
                    if (ReportMissing)
                        throw CompileError("Unable to resolve struct {0}", resolvable->name());
                }
            }

            for (auto& resolvable : Resolvable<FunctionDef>::Instances()) {
                if (!resolvable->value()) {
                    if (auto fn = Symbols.Functions.lookup(resolvable->name())) {
                        resolvable->resolve(fn);
                        continue;
                    }
                    if (ReportMissing)
                        throw CompileError("Unable to resolve function {0}", resolvable->name());
                }
            }
        }
    };
} // namespace pepper::ast
