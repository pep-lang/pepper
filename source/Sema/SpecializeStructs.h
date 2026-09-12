#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "Core/TypeSwitch.h"
#include "Sema/Specialization.h"
#include "Sema/Transform.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::sema {
    struct SpecializeStructs : public Transformer {
        DECLARE_RTTI(SpecializeStructs, Transformer);

        llvm::StringMap<StructDef*> structs;

        void run(Ref<Module> module) override {
            llvm::DenseSet<TypeName> done;
            for (auto& st : module->structs()) {
                structs[st->name] = st;
                done.insert(st->type);
            }

            for (const auto& spec : module->structSpecs()) {
                if (done.contains(spec->type))
                    continue;

                auto specialized = specialize(spec);
                module->insert(specialized);
                done.insert(spec->type);
            }
        }

        StructDef* specialize(const StructSpec* struct_spec) {
            PEP_TRACE_AST("  Specializing {0}", struct_spec->type.to_string());
            auto base = structs.lookup(struct_spec->type.name);
            if (!base) {
                throw CompileError(
                    struct_spec->source_loc, "Unable to specialize non-existent struct {0}", struct_spec->type.name);
            }

            Node::push_source(struct_spec->source_loc);
            auto specialized = new StructDef(struct_spec->type, struct_spec->type.to_string());
            Node::pop_source();
            specialized->generic_params.clear();
            StructSpecialization spec{base, struct_spec};

            apply(base, specialized, spec);

            return specialized;
        }

        struct StructSpecializer : Specializer {
            StructDef* struct_def;

            StructSpecializer(const StructSpecialization& spec, StructDef* st)
                : Specializer(spec)
                , struct_def(st) {}

            void visitNode(NodeRef& node) override {
                TypeSwitch<Node*>(node)
                    .Case<FieldDef>([this](FieldDef* field) {
                        assert(true);
                        field->parent = struct_def;
                    })
                    .Case<MethodDef>([this](MethodDef* method) { method->parent = struct_def; });
            }
        };

        void apply(StructDef* base, StructDef* specialized, const StructSpecialization& spec) {
            // replace types on field_members
            specialized->field_members.clone(base->field_members);

            // clone the ctor
            specialized->construct = base->construct->clone_as<ConstructorDef>();

            // replace types in method return types and params
            for (const auto& srcMethod : base->method_members) {
                // clone the method then specialize it
                auto method = srcMethod->clone_as<MethodDef>();
                specialized->method_members.push_back(method);

                // update special method_members once specialized
                if (method->name == "__dtor")
                    specialized->destruct = method;
                if (method->name == "__acquire")
                    specialized->acquire = method;
                if (method->name == "__release")
                    specialized->release = method;
            }

            // apply the specializer to the new struct
            StructSpecializer specializer{spec, specialized};
            specializer.visit(specialized);

            // fix up the constructor
            specialized->construct->name = spec.name.to_string();
            specialized->construct->type = spec.name;
        }
    };
} // namespace pepper::sema
