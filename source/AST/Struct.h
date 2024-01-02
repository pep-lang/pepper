
#pragma once

#include <string>

#include "AST/Functions.h"
#include "AST/Method.h"
#include "AST/Node.h"
#include "AST/Trait.h"
#include "AST/Variables.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/Vector.h"

namespace pepper::ast {

    struct StructDef;

    struct FieldDef : public VariableDef {
        DECLARE_RTTI(FieldDef, VariableDef);

        Resolvable<StructDef> Struct;

        FieldDef(const Resolvable<StructDef>& st,
                 const TypeName& type,
                 const Ident& name,
                 Expression* defaultValue = nullptr);

        Node* clone() const override;

        void visit(Visitor& visitor) override {
            VariableDef::visit(visitor);
            visitor.visit(Struct);
        }

        std::string toString() const override;
        std::string dump(int indent) const override;
    };

    struct StructDef
        : public Symbol
        , public ScopeTarget {
        DECLARE_RTTI(StructDef, Symbol);

        NodeList<TraitDef> Traits;

        TNodeRef<ConstructorDef> Constructor;
        TNodeRef<MethodDef> Destructor;
        TNodeRef<MethodDef> Acquire;
        TNodeRef<MethodDef> Release;
        NodeList<FieldDef> Fields;
        NodeList<MethodDef> Methods;
        // type parameters in struct decl
        Vector<Ident, 0> GenericParams;

        explicit StructDef(const TypeName& type, const Ident& name);
        StructDef(const StructDef& rhs) = default;
        void finish();

        void addFunction(FunctionDef* function) override {
            // Don't need to double-add these
            if (function == Constructor || function == Destructor) {
                return;
            }
            if (auto method = function->as<MethodDef>())
                Methods.emplace_back(method);
            // TODO: static functions
        }

        void addVariable(VariableDef* var) override {
            assert(var->is<FieldDef>() && "structs only contain fields");
            if (auto field = var->as<FieldDef>())
                Fields.emplace_back(field);
        }

        FieldDef* getField(const Ident& name) const;
        MethodDef* getMethod(const Ident& name) const;

        bool isGeneric() const {
            return !GenericParams.empty();
        }

        bool isConcrete() const {
            return !isGeneric();
        }

        Node* clone() const override;

        std::string toString() const override;
        std::string dump(int indent = 0) const override;

        void visit(Visitor& visitor) override {
            Symbol::visit(visitor);
            visitor.visit(Constructor);
            visitor.visit(Destructor);
            for (auto& field : Fields)
                visitor.visit(field);
            for (auto& method : Methods)
                visitor.visit(method);
        }
    };

    struct StructSpec : public Symbol {
        DECLARE_RTTI(StructSpec, Symbol);
        AST_NODE_POD_CLONE(StructSpec);

        StructSpec(const TypeName& type)
            : Symbol(type, type.toString()) {}

        std::string toString() const override;
        std::string dump(int indent) const override;
    };

    struct MemberRef : public SymbolRef {
        DECLARE_RTTI(MemberRef, SymbolRef);
        AST_NODE_POD_CLONE(MemberRef);

        TNodeRef<Expression> LHS;

        MemberRef(Expression* lhs, const Ident& fieldName)
            : SymbolRef(fieldName)
            , LHS(lhs) {}

        MemberRef(const MemberRef& ref)
            : SymbolRef(ref)
            , LHS(ref.LHS->cloneAs<Expression>()) {}

        std::string toString() const override {
            return nodeName() + std::string(llvm::formatv("({0}).{1}", LHS ? LHS->toString() : "unknown", Name));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} ({1}).{2}", Node::dump(indent), LHS ? LHS->dump() : "unknown", Name);
        }

        void visit(Visitor& visitor) override {
            SymbolRef::visit(visitor);
            visitor.visit(LHS);
        }
    };

    struct ThisDef : public VariableDef {
        DECLARE_RTTI(ThisDef, VariableDef)
        AST_NODE_POD_CLONE(ThisDef);

        ThisDef(const TypeName& structType, Expression* defaultValue)
            : VariableDef(structType, "this", defaultValue) {}
    };

    struct ThisRef : public SymbolRef {
        DECLARE_RTTI(ThisRef, SymbolRef);
        AST_NODE_POD_CLONE(ThisRef);

        ThisRef()
            : SymbolRef("this") {}
    };
} // namespace pepper::ast
