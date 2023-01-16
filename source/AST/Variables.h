
#pragma once

#include "AST/Node.h"
#include "Core/Common.h"
#include "Core/Ident.h"

namespace pepper::ast {
    struct VariableDef : public Symbol {
        DECLARE_RTTI(VariableDef, Symbol);
        AST_NODE_POD_CLONE(VariableDef);

        Ref<Expression> Default;

        VariableDef(
            const TypeName& type, const Ident& identifier, Ref<Expression> defaultValue = nullptr, bool hidden = false)
            : Symbol(type, identifier, hidden)
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
            std::string def;
            if (Default)
                def = std::string(llvm::formatv(" = {0}", Default->dump()));
            return llvm::formatv("{0} {1} {2}{3}", Node::dump(indent), Type, Name, def);
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

    struct SymbolRef : public Expression {
        DECLARE_RTTI(SymbolRef, Expression);
        AST_NODE_POD_CLONE(SymbolRef);

        Ident Name;
        TypeName Type;

      public:
        explicit SymbolRef(const Ident& identifier)
            : Name(identifier) {
            Type.Name.clear();
        }

        explicit SymbolRef(const TypeName& typeName)
            : Type(typeName)
            , Name(typeName.toString()) {
            if (Type.GenericTypes.empty()) {
                Type.Name.clear();
            }
        }

        const TypeName& type() const override {
            if (!Type.Name.empty())
                return Type;
            return Expression::type();
        }

        std::string toString() const override {
            return std::string(llvm::formatv("{0} {1}", Node::toString(), Name));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), Name);
        }
    };
} // namespace pepper::ast
