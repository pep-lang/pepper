
#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Sema/Transform.h"

namespace pepper::sema {
    struct GatherGenerics : public Transformer {
        DECLARE_RTTI(GatherGenerics, Transformer);

        llvm::DenseSet<TypeName> functions;
        llvm::DenseSet<TypeName> structs;

        struct Gatherer : Visitor {
            llvm::DenseSet<TypeName>& functions;
            llvm::DenseSet<TypeName>& structs;

            Gatherer(llvm::DenseSet<TypeName>& functions, llvm::DenseSet<TypeName>& structs)
                : functions(functions)
                , structs(structs) {}

            void visitType(TypeName& type) override {
                if (type.is_generic() && !type.name.starts_with("__"))
                    structs.insert(type);
            }

            void visitNode(NodeRef& node) override {
                if (auto call = node->as<FunctionCall>()) {
                    const TypeName& type = call->target;
                    // Do not record specializations for intrinsics
                    if (type.name.starts_with("__"))
                        return;
                    if (type.is_generic()) {
                        functions.insert(type);
                    }
                }
            }
        };

        void run(Ref<Module> module) override {
            SymbolTable symbols(*module);
            auto gatherer = Gatherer(functions, structs);
            for (auto& st : module->structs()) {
                gatherer.visit(st);
            }
            for (auto& fn : module->functions()) {
                gatherer.visit(fn);
            }
            for (auto& ext : module->extensions()) {
                gatherer.visit(ext);
            }

            llvm::DenseSet<TypeName> struct_specs;
            for (const auto& structSpec : module->structSpecs())
                struct_specs.insert(structSpec->type);
            llvm::DenseSet<TypeName> func_specs;
            for (const auto& funcSpec : module->function_specs())
                func_specs.insert(funcSpec->type);

            for (const auto& struct_spec : structs) {
                if (struct_specs.contains(struct_spec))
                    continue;
                if (auto st = symbols.structs.lookup(struct_spec.name)) {
                    if (st->type == struct_spec)
                        continue;
                    PEP_TRACE_AST("Generic struct {0}", struct_spec.to_string());
                    Node::push_source(st->source_loc);
                    module->insert(new StructSpec(struct_spec));
                    Node::pop_source();
                    struct_specs.insert(struct_spec);
                }
            }

            for (const auto& type : functions) {
                if (func_specs.contains(type))
                    continue;
                // if the function call is actually a constructor
                if (auto st = symbols.structs.lookup(type.name)) {
                    if (st->type == type || struct_specs.contains(type))
                        continue;
                    PEP_TRACE_AST("Generic struct {0}", type.to_string());
                    module->insert(new StructSpec(type));
                    continue;
                }

                if (auto fn = symbols.functions.lookup(type.name)) {
                    if (fn->type == type)
                        continue;
                }

                PEP_TRACE_AST("Generic function call {0}", type.to_string());
                module->insert(new FunctionSpec(type));
            }
        }
    };
} // namespace pepper::sema
