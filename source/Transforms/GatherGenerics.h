
#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Transforms/Transform.h"

namespace pepper::ast {
    struct GatherGenerics : public Transformer {
        DECLARE_RTTI(GatherGenerics, Transformer);

        llvm::DenseSet<TypeName> Generics;

        struct Gatherer : Visitor {
            llvm::DenseSet<TypeName>& Generics;

            Gatherer(llvm::DenseSet<TypeName>& generics)
                : Generics(generics) {}

            void visitType(TypeName& type) override {
                if (type.isGeneric())
                    Generics.insert(type);
            }

            void visitNode(NodeRef& node) override {
                if (auto call = node->as<FunctionCall>()) {
                    const TypeName& type = call->Target;
                    if (type.isGeneric()) {
                        Generics.insert(type);
                    }
                }
            }
        };

        void run(Ref<AST> parseTree) override {
            SymbolTable Symbols(*parseTree);
            auto gatherer = Gatherer(Generics);
            for (auto& st : parseTree->structs()) {
                gatherer.visit(st);
            }
            for (auto& fn : parseTree->functions()) {
                gatherer.visit(fn);
            }
            for (auto& ext : parseTree->extensions()) {
                gatherer.visit(ext);
            }

            for (const auto& type : Generics) {
                if (auto st = Symbols.Structs.lookup(type.Name)) {
                    if (st->Type == type)
                        continue;
                    PEP_TRACE_AST("Generic struct {0}", type.toString());
                    parseTree->insert(new StructSpec(type));
                    continue;
                }
                PEP_TRACE_AST("Generic function call {0}", type.toString());
                parseTree->insert(new FunctionSpec(type));
            }
        }
    };
} // namespace pepper::ast
