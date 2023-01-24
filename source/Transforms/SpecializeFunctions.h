#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/TypeSwitch.h"
#include "Transforms/Specialization.h"
#include "Transforms/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct SpecializeFunctions : public Transformer {
        DECLARE_RTTI(SpecializeFunctions, Transformer);

        llvm::StringMap<FunctionDef*> Functions;
        llvm::StringMap<StructDef*> Structs;

        void run(Ref<AST> parseTree) override {
            for (auto& function : parseTree->functions()) {
                Functions[function->Name] = function;
            }
            for (auto& st : parseTree->structs()) {
                Structs[st->Name] = st;
                Functions[st->Constructor->Name] = st->Constructor;
            }
            for (const auto& spec : parseTree->functionSpecs()) {
                if (Structs.lookup(spec->Name))
                    continue;
                auto specialized = specialize(spec);
                parseTree->insert(specialized);
            }
        }

        FunctionDef* specialize(const FunctionSpec* functionSpec) {
            PEP_TRACE_AST("  Specializing {0}", functionSpec->Type.toString());
            auto base = Functions.lookup(functionSpec->Type.Name);
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
            specialized->GenericParams.clear();

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
