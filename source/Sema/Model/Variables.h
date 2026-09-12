
#pragma once

#include "Sema/Model/Node.h"
#include "Core/Common.h"
#include "Core/Ident.h"

namespace pepper::sema {
    struct VariableDef : public Symbol {
        DECLARE_RTTI(VariableDef, Symbol);
        SEMA_NODE_POD_CLONE(VariableDef);

        TNodeRef<Expression> default_value;

        VariableDef(const TypeName& type = {}, const Ident& identifier = {}, Expression* def_value = nullptr, bool hidden = false)
            : Symbol(type, identifier, hidden)
            , default_value(def_value) {}

        VariableDef(const VariableDef& rhs)
            : Symbol(rhs)
            , default_value{rhs.default_value ? rhs.default_value->clone_as<Expression>() : nullptr} {}

        std::string to_string() const override {
            auto str = std::string(llvm::formatv("{0}: {1} {2}", node_name(), type, name));
            if (default_value)
                str += std::string(llvm::formatv(" = {0}", default_value->to_string()));
            return str;
        }

        std::string dump(int indent) const override {
            std::string def;
            if (default_value)
                def = std::string(llvm::formatv(" = {0}", default_value->dump()));
            return llvm::formatv("{0} {1} {2}{3}", Node::dump(indent), type, name, def);
        }

        void visit(Visitor& visitor) override {
            Symbol::visit(visitor);
            if (default_value)
                visitor.visit(default_value);
        }
    };

    struct ParamDef : public VariableDef {
        DECLARE_RTTI(ParamDef, VariableDef);
        SEMA_NODE_POD_CLONE(ParamDef);

      public:
        using VariableDef::VariableDef;
    };

    struct SymbolRef : public Expression {
        DECLARE_RTTI(SymbolRef, Expression);
        SEMA_NODE_POD_CLONE(SymbolRef);

        Ident id;
        TypeName ty = TypeName::Auto;

      public:
        explicit SymbolRef(const Ident& identifier)
            : id(identifier) {}

        explicit SymbolRef(const TypeName& typeName)
            : ty(typeName)
            , id(typeName.to_string()) {}

        const TypeName& type() const override {
            return ty;
        }

        std::string to_string() const override {
            return std::string(llvm::formatv("{0}: {1} {2}", node_name(), ty.to_string(), id));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1} {2}", Node::dump(indent), ty.to_string(), id);
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(ty);
        }
    };
} // namespace pepper::sema
