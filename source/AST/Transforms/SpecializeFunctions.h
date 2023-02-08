#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/TypeSwitch.h"
#include "Specialization.h"
#include "Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct SpecializeFunctions : public Transformer {
        DECLARE_RTTI(SpecializeFunctions, Transformer);

        SymbolTable Symbols;

        void run(Ref<AST> parseTree) override {
            Symbols = SymbolTable(*parseTree);

            for (const auto& spec : parseTree->functionSpecs()) {
                if (Symbols.Structs.lookup(spec->Name))
                    continue;
                if (auto specialized = specialize(spec))
                    parseTree->insert(specialized);
            }
        }

        FunctionDef* specialize(const FunctionSpec* functionSpec) {
            if (auto function = Symbols.Functions.lookup(functionSpec->Type.toString())) {
                PEP_TRACE_AST("  Found existing specialization for {0}", functionSpec->Type.toString());
                return nullptr;
            }
            PEP_TRACE_AST("  Specializing {0}", functionSpec->Type.toString());
            auto base = Symbols.Functions.lookup(functionSpec->Type.Name)->as<FunctionDef>();
            if (!base) {
                throw CompileError(functionSpec->Source,
                                   "Unable to specialize non-existent function {0} to {1}",
                                   functionSpec->Type.Name,
                                   functionSpec->Type.toString());
            }

            FunctionDef* specialized;
            if (base->is<MethodDef>())
                specialized = base->cloneAs<MethodDef>();
            else
                specialized = base->cloneAs<FunctionDef>();

            specialized->Type = functionSpec->Type;
            specialized->Name = functionSpec->Type.toString();

            FunctionSpecialization spec{base, functionSpec};
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
} // namespace pepper::ast
