
#pragma once

#include "AST/Node.h"
#include "Core/Common.h"
#include "Core/Ident.h"

namespace pepper::ast {
    struct VariableDef : public Symbol {
        DECLARE_RTTI(VariableDef, Symbol);
        AST_NODE_POD_CLONE(VariableDef);

        Ref<Expression> Default;

        VariableDef(const TypeName& type, const Ident& identifier, Ref<Expression> defaultValue = nullptr)
            : Symbol(type, identifier)
            , Default(std::move(defaultValue)) {
        }

        VariableDef(const VariableDef& rhs)
            : Symbol(rhs)
            , Default{rhs.Default ? rhs.Default->cloneAs<Expression>() : Ref<Expression>()} {
        }

        std::string toString() const override {
            auto str = std::string(llvm::formatv("{0} {1} {2}", Node::toString(), Type, Name));
            if (Default)
                str += std::string(llvm::formatv(" = {0}", Default->toString()));
            return str;
        }

        std::string dump(int indent) const override {
            auto str = std::string(llvm::formatv("{0} {1}", Type, Name));
            if (Default)
                str += std::string(llvm::formatv(" = {0}", Default->toString()));
            return Node::dump(indent) + str;
        }

        void specialize(const Specialization& spec) override {
            Symbol::specialize(spec);
            if (Default)
                Default->specialize(spec);
        }
    };

    struct ParamDef : public VariableDef {
        DECLARE_RTTI(ParamDef, VariableDef);
        AST_NODE_POD_CLONE(ParamDef);

      public:
        using VariableDef::VariableDef;
    };

    struct VariableRef : public Expression {
        DECLARE_RTTI(VariableRef, Expression);
        AST_NODE_POD_CLONE(VariableRef);

      private:
        Ident Identifier;

      public:
        VariableRef(const Ident& identifier)
            : Identifier(identifier) {
        }

        const Ident& identifier() const {
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
