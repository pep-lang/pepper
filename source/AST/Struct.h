//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <string>

#include "AST/Functions.h"
#include "AST/Node.h"
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

        std::string toString() const override;
        std::string dump(int indent) const override;
    };

    struct ConstructorDef : public FunctionDef {
        DECLARE_RTTI(ConstructorDef, FunctionDef);
        AST_NODE_POD_CLONE(ConstructorDef);

        class StructDef* Struct;

        ConstructorDef(class StructDef* st,
                       const TypeName& returnType,
                       const TypeName& name,
                       const Params& params = Params(),
                       bool varargs = false)
            : FunctionDef(returnType, name, params, varargs)
            , Struct(st) {}
    };

    struct MethodDef : public FunctionDef {
        DECLARE_RTTI(MethodDef, FunctionDef);

        Resolvable<StructDef> Struct;

      public:
        MethodDef(const TypeName& structName,
                  const TypeName& returnType,
                  const TypeName& name,
                  const Params& params = Params(),
                  bool vararg = false);

        Node* clone() const override;

        std::string signature() const override;
        std::string toString() const override;
        std::string dump(int indent) const override;
    };

    struct StructDef
        : public Symbol
        , public ScopeTarget {
        DECLARE_RTTI(StructDef, Symbol);

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

    struct ExtensionDef
        : public Node
        , public ScopeTarget {
        DECLARE_RTTI(ExtensionDef, Node);
        AST_NODE_POD_CLONE(ExtensionDef);

        Resolvable<StructDef> Target;
        NodeList<MethodDef> Methods;

        ExtensionDef(const TypeName& target)
            : ScopeTarget(this)
            , Target(target) {}

        ExtensionDef(const ExtensionDef& ext)
            : ScopeTarget(this)
            , Target(ext.Target) {
            Methods.clone(ext.Methods);
        }

        void addFunction(FunctionDef* function) override {
            if (auto method = function->as<MethodDef>())
                Methods.emplace_back(method);
            // TODO: static functions
        }

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            visitor.visit(Target);
            for (auto& method : Methods)
                visitor.visit(method);
        }

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
            return Node::toString() + std::string(llvm::formatv("({0}).{1}", LHS ? LHS->toString() : "unknown", Name));
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} ({1}).{2}", Node::dump(indent), LHS ? LHS->dump() : "unknown", Name);
        }

        void visit(Visitor& visitor) override {
            SymbolRef::visit(visitor);
            visitor.visit(LHS);
        }
    };

    struct MethodCall : public Expression {
        DECLARE_RTTI(MethodCall, Expression);
        AST_NODE_POD_CLONE(MethodCall);

        TypeName Type;
        TNodeRef<Expression> This;
        const Ident Name;
        ExprList Args;

        MethodCall(Expression* thisRef, const Ident& methodName, const ExprList& args = {})
            : This(thisRef)
            , Name(methodName) {
            Args.clone(args);
        }

        MethodCall(const MethodCall& m)
            : Expression(m)
            , Type(m.Type)
            , This(m.This->cloneAs<Expression>())
            , Name(m.Name) {
            Args.clone(m.Args);
        }

        const TypeName& type() const override {
            return Type;
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(Type);
            visitor.visit(This);
            for (auto& arg : Args)
                visitor.visit(arg);
        }

        std::string dump(int indent) const override;
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
