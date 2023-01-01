
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
            auto str = std::string(llvm::formatv("{0} {1} {2}", Node::toString(), type(), identifier()));
            if (Default)
                str += std::string(llvm::formatv(" = {0}", Default->toString()));
            return str;
        }

        std::string dump(int indent) const override {
            auto str = std::string(llvm::formatv("{0} {1}", type(), identifier()));
            if (Default)
                str += std::string(llvm::formatv(" = {0}", Default->toString()));
            return Node::dump(indent) + str;
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
            return std::string(llvm::formatv("{0} {1}", Node::toString(), identifier()));
        }

        std::string dump(int indent) const override {
            return Node::dump(indent) + Identifier;
        }
    };
} // namespace pepper::ast
