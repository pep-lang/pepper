#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/TypeSwitch.h"
#include "Sema/Specialization.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::sema {
    struct SpecializeFunctions : public Transformer {
        DECLARE_RTTI(SpecializeFunctions, Transformer);

        SymbolTable symbols;

        void run(Ref<Module> module) override {
            symbols = SymbolTable(*module);

            for (const auto& spec : module->function_specs()) {
                if (symbols.structs.lookup(spec->name))
                    continue;
                if (auto specialized = specialize(spec))
                    module->insert(specialized);
            }
        }

        FunctionDef* specialize(const FunctionSpec* function_spec) {
            if (auto function = symbols.functions.lookup(function_spec->type.to_string())) {
                PEP_TRACE_AST("  Found existing specialization for {0}", function_spec->type.to_string());
                return nullptr;
            }
            PEP_TRACE_AST("  Specializing {0}", function_spec->type.to_string());
            auto base = symbols.functions.lookup(function_spec->type.name)->as<FunctionDef>();
            if (!base) {
                throw CompileError(function_spec->source_loc,
                                   "Unable to specialize non-existent function {0} to {1}",
                                   function_spec->type.name,
                                   function_spec->type.to_string());
            }

            FunctionDef* specialized;
            if (base->is<MethodDef>())
                specialized = base->clone_as<MethodDef>();
            else
                specialized = base->clone_as<FunctionDef>();

            specialized->type = function_spec->type;
            specialized->name = function_spec->type.to_string();

            FunctionSpecialization spec{base, function_spec};
            apply(specialized, spec);

            return specialized;
        }

        struct FunctionSpecializer : Specializer {
            using Specializer::Specializer;

            //            void visitNode(NodeRef node) override {
            //                TypeSwitch<Node>(node).Case<FunctionDef>(
            //                    [this](FunctionDef* function) { specializeFunction(function); });
            //            }
        };

        void apply(FunctionDef* specialized, const FunctionSpecialization& spec) {
            // apply the specializer to the new struct
            FunctionSpecializer specializer{spec};
            specializer.visit(specialized);
        }
    };
} // namespace pepper::sema
