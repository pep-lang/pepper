
#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Sema/Transform.h"

namespace pepper::ast {
    struct GatherGenerics : public Transformer {
        DECLARE_RTTI(GatherGenerics, Transformer);

        llvm::DenseSet<TypeName> Functions;
        llvm::DenseSet<TypeName> Structs;

        struct Gatherer : Visitor {
            llvm::DenseSet<TypeName>& Functions;
            llvm::DenseSet<TypeName>& Structs;

            Gatherer(llvm::DenseSet<TypeName>& functions, llvm::DenseSet<TypeName>& structs)
                : Functions(functions)
                , Structs(structs) {}

            void visitType(TypeName& type) override {
                if (type.isGeneric() && !type.Name.starts_with("__"))
                    Structs.insert(type);
            }

            void visitNode(NodeRef& node) override {
                if (auto call = node->as<FunctionCall>()) {
                    const TypeName& type = call->Target;
                    // Do not record specializations for intrinsics
                    if (type.Name.starts_with("__"))
                        return;
                    if (type.isGeneric()) {
                        Functions.insert(type);
                    }
                }
            }
        };

        void run(Ref<AST> parseTree) override {
            SymbolTable Symbols(*parseTree);
            auto gatherer = Gatherer(Functions, Structs);
            for (auto& st : parseTree->structs()) {
                gatherer.visit(st);
            }
            for (auto& fn : parseTree->functions()) {
                gatherer.visit(fn);
            }
            for (auto& ext : parseTree->extensions()) {
                gatherer.visit(ext);
            }

            llvm::DenseSet<TypeName> structSpecs;
            for (const auto& structSpec : parseTree->structSpecs())
                structSpecs.insert(structSpec->Type);
            llvm::DenseSet<TypeName> funcSpecs;
            for (const auto& funcSpec : parseTree->functionSpecs())
                funcSpecs.insert(funcSpec->Type);

            for (const auto& structSpec : Structs) {
                if (structSpecs.contains(structSpec))
                    continue;
                if (auto st = Symbols.Structs.lookup(structSpec.Name)) {
                    if (st->Type == structSpec)
                        continue;
                    PEP_TRACE_AST("Generic struct {0}", structSpec.toString());
                    parseTree->insert(new StructSpec(structSpec));
                    structSpecs.insert(structSpec);
                }
            }

            for (const auto& type : Functions) {
                if (funcSpecs.contains(type))
                    continue;
                // if the function call is actually a constructor
                if (auto st = Symbols.Structs.lookup(type.Name)) {
                    if (st->Type == type || structSpecs.contains(type))
                        continue;
                    PEP_TRACE_AST("Generic struct {0}", type.toString());
                    parseTree->insert(new StructSpec(type));
                    continue;
                }

                if (auto fn = Symbols.Functions.lookup(type.Name)) {
                    if (fn->Type == type)
                        continue;
                }

                PEP_TRACE_AST("Generic function call {0}", type.toString());
                parseTree->insert(new FunctionSpec(type));
            }
        }
    };
} // namespace pepper::ast
