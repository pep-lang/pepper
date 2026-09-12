
#pragma once

#include <string>

#include "Sema/Model/Functions.h"
#include "Sema/Model/Method.h"
#include "Sema/Model/Node.h"
#include "Sema/Model/Trait.h"
#include "Sema/Model/Variables.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper::sema {

    struct StructDef;

    struct FieldDef : public VariableDef {
        DECLARE_RTTI(FieldDef, VariableDef);

        Resolvable<StructDef> parent;

        FieldDef(const Resolvable<StructDef>& st,
                 const TypeName& type = {},
                 const Ident& name = {},
                 Expression* defaultValue = nullptr);

        Node* clone() const override;

        void visit(Visitor& visitor) override {
            VariableDef::visit(visitor);
            visitor.visit(parent);
        }

        std::string to_string() const override;
        std::string dump(int indent) const override;
    };

    struct StructDef
        : public Symbol
        , public ScopeTarget {
        DECLARE_RTTI(StructDef, Symbol);

        NodeList<TraitDef> traits;

        TNodeRef<ConstructorDef> construct;
        TNodeRef<MethodDef> destruct;
        TNodeRef<MethodDef> acquire;
        TNodeRef<MethodDef> release;
        NodeList<FieldDef> field_members;
        NodeList<MethodDef> method_members;
        // type parameters in struct decl
        Vector<Ident, 0> generic_params;

        explicit StructDef(const TypeName& type = {}, const Ident& name = {});
        StructDef(const StructDef& rhs) = default;
        void finish();

        void add_function(FunctionDef* function) override {
            // Don't need to double-add these
            if (function == construct || function == destruct) {
                return;
            }
            if (auto method = function->as<MethodDef>())
                method_members.emplace_back(method);
            // TODO: static functions
        }

        void add_field(VariableDef* var) override {
            assert(var->is<FieldDef>() && "structs only contain field_members");
            if (auto field = var->as<FieldDef>())
                field_members.emplace_back(field);
        }

        FieldDef* get_field(const Ident& name) const;
        MethodDef* get_method(const Ident& name) const;

        bool is_generic() const {
            return !generic_params.empty();
        }

        bool is_concrete() const {
            return !is_generic();
        }

        Node* clone() const override;

        std::string to_string() const override;
        std::string dump(int indent = 0) const override;

        void visit(Visitor& visitor) override {
            Symbol::visit(visitor);
            visitor.visit(construct);
            visitor.visit(destruct);
            for (auto& field : field_members)
                visitor.visit(field);
            for (auto& method : method_members)
                visitor.visit(method);
        }
    };

    struct StructSpec : public Symbol {
        DECLARE_RTTI(StructSpec, Symbol);
        SEMA_NODE_POD_CLONE(StructSpec);

        StructSpec(const TypeName& type)
            : Symbol(type, type.to_string()) {}

        std::string to_string() const override;
        std::string dump(int indent) const override;
    };

    struct MemberRef : public SymbolRef {
        DECLARE_RTTI(MemberRef, SymbolRef);
        SEMA_NODE_POD_CLONE(MemberRef);

        TNodeRef<Expression> lhs;

        MemberRef(Expression* lhs, const Ident& fieldName)
            : SymbolRef(fieldName)
            , lhs(lhs) {}

        MemberRef(const MemberRef& ref)
            : SymbolRef(ref)
            , lhs(ref.lhs->clone_as<Expression>()) {}

        std::string to_string() const override {
            return node_name() + std::string(llvm::formatv("({0}).{1}", lhs ? lhs->to_string() : "unknown", id));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} ({1}).{2}", Node::dump(indent), lhs ? lhs->dump() : "unknown", id);
        }

        void visit(Visitor& visitor) override {
            SymbolRef::visit(visitor);
            visitor.visit(lhs);
        }
    };

    struct ThisDef : public VariableDef {
        DECLARE_RTTI(ThisDef, VariableDef)
        SEMA_NODE_POD_CLONE(ThisDef);

        ThisDef(const TypeName& structType, Expression* defaultValue)
            : VariableDef(structType, "this", defaultValue) {}
    };

    struct ThisRef : public SymbolRef {
        DECLARE_RTTI(ThisRef, SymbolRef);
        SEMA_NODE_POD_CLONE(ThisRef);

        ThisRef()
            : SymbolRef("this") {}
    };
} // namespace pepper::sema
