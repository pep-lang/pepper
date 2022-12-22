
#pragma once

#include "Core/Common.h"
#include <string>

namespace llvm {
    class Type;
}

namespace pepper::ast {
    class VariableDef : public Symbol {
        DECLARE_RTTI(VariableDef, Symbol);

      public:
        VariableDef(llvm::Type* type, const std::string& name)
            : Symbol(type, name) {
        }
    };

    class FieldDef : public VariableDef {
        DECLARE_RTTI(FieldDef, VariableDef);

      public:
        Ref<StructDef> Struct;

        FieldDef(Ref<StructDef> strct, llvm::Type* type, const std::string& name)
            : VariableDef(type, name) {
            Struct = strct;
        }
    };

    class ConstantDef : public VariableDef {
        DECLARE_RTTI(ConstantDef, VariableDef);

      public:
        ConstantDef(llvm::Type* type, const std::string& name)
            : VariableDef(type, name) {
        }
    };

    class VariableRef : public Expression {
        DECLARE_RTTI(VariableRef, Expression);

      private:
        llvm::Type* Type;
        std::string Identifier;

      public:
        VariableRef(llvm::Type* type, const std::string identifier)
            : Type(type)
            , Identifier(identifier) {
        }

        llvm::Type* type() override const {
            return Type;
        }

        const std::string& identifier() const {
            return Identifier;
        }
    };
} // namespace pepper::ast
