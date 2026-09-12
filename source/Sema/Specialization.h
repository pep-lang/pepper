#pragma once

#include "Sema/Model/Nodes.h"
#include "Core/Exceptions.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::sema {
    struct Specialization {
        DECLARE_RTTI(Specialization);
        using GenericTypeMap = llvm::StringMap<TypeName>;
        TypeName name;
        GenericTypeMap type_map;

      protected:
        Specialization() = default;
    };

    struct StructSpecialization : public Specialization {
        DECLARE_RTTI(StructSpecialization, Specialization);
        StructDef* struct_def;

        StructSpecialization(StructDef* base, const StructSpec* spec)
            : struct_def(base) {
            name = spec->type;
            // map params -> args
            for (int idx = 0; idx < struct_def->generic_params.size(); ++idx) {
                const auto& param = struct_def->generic_params[idx];
                const auto& type = spec->type.sub_types[idx];
                type_map[param] = type;
            }
        }
    };

    struct FunctionSpecialization : public Specialization {
        DECLARE_RTTI(FunctionSpecialization, Specialization);
        FunctionDef* function_def;

        FunctionSpecialization(FunctionDef* base, const FunctionSpec* spec)
            : function_def(base) {
            name = spec->type;
            if (base->type.sub_types.size() != spec->type.sub_types.size())
                throw CompileError(spec->source_loc,
                                   "Incorrect number of generic types in specialization of {0}: got {1}, expected {2}",
                                   base->name,
                                   spec->type.sub_types.size(),
                                   base->type.sub_types.size());
            // map params -> args
            for (int idx = 0; idx < base->type.sub_types.size(); ++idx) {
                const auto& param = base->type.sub_types[idx].name;
                const auto& type = spec->type.sub_types[idx];
                type_map[param] = type;
            }
        }
    };

    struct Specializer : Visitor {
        const Specialization& Spec;

        Specializer(const Specialization& spec)
            : Spec(spec) {}

        static void replace(TypeName& type, const Ident& param_name, const TypeName& type_arg) {
            if (type.name == param_name) {
                type = type_arg;
            }
            for (auto& arg : type.sub_types) {
                replace(arg, param_name, type_arg);
            }
        }

        void specializeType(TypeName& type) {
            for (const auto& generic : Spec.type_map) {
                replace(type, generic.getKey().str(), generic.getValue());
            }
        }

        void visitType(TypeName& type) override {
            specializeType(type);
        }
    };
} // namespace pepper::sema
