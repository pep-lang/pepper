
#pragma once

#include "AST/Node.h"
#include "Core/Common.h"
#include "Core/Name.h"

namespace pepper::ast {
    class VariableDef : public Symbol {
        DECLARE_RTTI(VariableDef, Symbol);

        Ref<Expression> Default;

      public:
        VariableDef(const Name& type, const Name& identifier, Ref<Expression> defaultValue = nullptr)
            : Symbol(type, identifier)
            , Default(defaultValue) {
        }

        Ref<Expression> defaultValue() const {
            return Default;
        }

        void setDefaultValue(Ref<Expression> newDefault) {
            Default = newDefault;
        }

        std::string toString() const override {
            return Node::toString() +
                   std::string(
                       llvm::formatv("{0} {1} = {2}", type(), identifier(), Default ? Default->toString() : "default"));
        }
    };

    class ParamDef : public VariableDef {
        DECLARE_RTTI(ParamDef, VariableDef);

      public:
        using VariableDef::VariableDef;
    };

    class ConstantDef : public VariableDef {
        DECLARE_RTTI(ConstantDef, VariableDef);

      public:
        ConstantDef(const Name& type, const Name& name)
            : VariableDef(type, name) {
        }
    };

    class VariableRef : public Expression {
        DECLARE_RTTI(VariableRef, Expression);

      private:
        const Name Identifier;

      public:
        VariableRef(const Name& identifier)
            : Identifier(identifier) {
        }

        const Name& identifier() const {
            return Identifier;
        }

        std::string toString() const override {
            return Node::toString() + identifier();
        }
    };
} // namespace pepper::ast
