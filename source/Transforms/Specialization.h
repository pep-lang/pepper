#pragma once

#include "AST/Nodes.h"
#include "Core/RTTI.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    struct Specialization {
        DECLARE_RTTI(Specialization);
        using GenericTypeMap = llvm::StringMap<TypeName>;
        TypeName Name;
        GenericTypeMap TypeMap;

      protected:
        Specialization() = default;
    };

    struct StructSpecialization : public Specialization {
        DECLARE_RTTI(StructSpecialization, Specialization);
        StructDef* Struct;

        StructSpecialization(StructDef* structDef, const StructSpec* spec)
            : Struct(structDef) {
            Name = spec->Type;
            // map params -> args
            for (int idx = 0; idx < Struct->GenericParams.size(); ++idx) {
                const auto& param = Struct->GenericParams[idx];
                const auto& type = spec->Type.GenericTypes[idx];
                TypeMap[param] = type;
            }
        }
    };

    struct FunctionSpecialization : public Specialization {
        DECLARE_RTTI(FunctionSpecialization, Specialization);
        FunctionDef* Function;

        FunctionSpecialization(FunctionDef* base, const FunctionSpec* spec)
            : Function(base) {
            Name = spec->Type;
            if (base->GenericParams.size() != spec->Type.GenericTypes.size())
                throw CompileError(spec->Source,
                                   "Incorrect number of generic types in specialization of {0}: got {1}, expected {2}",
                                   base->Name,
                                   spec->Type.GenericTypes.size(),
                                   base->GenericParams.size());
            // map params -> args
            for (int idx = 0; idx < base->GenericParams.size(); ++idx) {
                const auto& param = base->GenericParams[idx];
                const auto& type = spec->Type.GenericTypes[idx];
                TypeMap[param] = type;
            }
        }
    };

    struct Specializer : Visitor {
        const Specialization& Spec;

        Specializer(const Specialization& spec)
            : Spec(spec) {}

        static void replace(TypeName& type, const Ident& genericParam, const TypeName& genericArg) {
            if (type.Name == genericParam) {
                type.Name = genericArg;
            }
            for (auto& arg : type.GenericTypes) {
                replace(arg, genericParam, genericArg);
            }
        }

        void specializeType(TypeName& type) {
            for (const auto& generic : Spec.TypeMap) {
                replace(type, generic.getKey().str(), generic.getValue());
            }
        }

        void visitType(TypeName& type) override {
            specializeType(type);
        }
    };
} // namespace pepper::ast