#pragma once

#include "AST/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/TypeSwitch.h"
#include "Transforms/Specialization.h"
#include "Transforms/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct SpecializeStructs : public Transformer {
        DECLARE_RTTI(SpecializeStructs, Transformer);

        llvm::StringMap<StructDef*> Structs;

        void run(Ref<AST> parseTree) override {
            llvm::DenseSet<TypeName> done;
            for (auto& st : parseTree->structs()) {
                Structs[st->Name] = st;
                done.insert(st->Type);
            }

            for (const auto& spec : parseTree->structSpecs()) {
                if (done.contains(spec->Type))
                    continue;

                auto specialized = specialize(spec);
                parseTree->insert(specialized);
                parseTree->insert(specialized->Constructor);
                done.insert(spec->Type);
            }
        }

        StructDef* specialize(const StructSpec* structSpec) {
            PEP_TRACE_AST("  Specializing {0}", structSpec->Type.toString());
            auto base = Structs.lookup(structSpec->Type.Name);
            if (!base) {
                throw CompileError(
                    structSpec->Source, "Unable to specialize non-existent struct {0}", structSpec->Type.Name);
            }

            auto specialized = new StructDef(structSpec->Type, structSpec->Type.toString());
            specialized->GenericParams.clear();
            StructSpecialization spec{base, structSpec};

            apply(base, specialized, spec);

            return specialized;
        }

        struct StructSpecializer : Specializer {
            StructDef* Struct;

            StructSpecializer(const StructSpecialization& spec, StructDef* st)
                : Specializer(spec)
                , Struct(st) {}

            void visitNode(NodeRef& node) override {
                TypeSwitch<Node*>(node)
                    .Case<FieldDef>([this](FieldDef* field) {
                        assert(true);
                        field->Struct = Struct;
                    })
                    .Case<MethodDef>([this](MethodDef* method) { method->Struct = Struct; });
            }
        };

        void apply(StructDef* base, StructDef* specialized, const StructSpecialization& spec) {
            // replace types on fields
            specialized->Fields.clone(base->Fields);

            // clone the ctor
            specialized->Constructor = base->Constructor->cloneAs<FunctionDef>();

            // replace types in method return types and params
            for (const auto& srcMethod : base->Methods) {
                // clone the method then specialize it
                auto method = srcMethod->cloneAs<MethodDef>();
                specialized->Methods.push_back(method);

                // update special methods once specialized
                if (method->Name == "__dtor")
                    specialized->Destructor = method;
                if (method->Name == "__acquire")
                    specialized->Acquire = method;
                if (method->Name == "__release")
                    specialized->Release = method;
            }

            // apply the specializer to the new struct
            StructSpecializer specializer{spec, specialized};
            specializer.visit(specialized);

            // fix up the constructor
            specialized->Constructor->Name = spec.Name.toString();
            specialized->Constructor->Type = spec.Name;
        }
    };
} // namespace pepper::ast
