#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct ResolveResolvables : public Transformer {
        DECLARE_RTTI(ResolveResolvables, Transformer);

        SymbolTable Symbols;

        void run(Ref<AST> parseTree) override {
            Symbols = SymbolTable(*parseTree);

            for (auto& resolvable : Resolvable<StructDef>::Instances()) {
                if (!resolvable->value()) {
                    if (auto st = Symbols.Structs.lookup(resolvable->name())) {
                        resolvable->resolve(st);
                        continue;
                    }
                }
            }

            for (auto& resolvable : Resolvable<FunctionDef>::Instances()) {
                if (!resolvable->value()) {
                    if (auto fn = Symbols.Functions.lookup(resolvable->name())) {
                        resolvable->resolve(fn);
                        continue;
                    }
                }
            }
        }
    };
} // namespace pepper::ast
