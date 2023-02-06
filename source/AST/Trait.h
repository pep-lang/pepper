
#pragma once

#include "AST/Extension.h"

namespace pepper::ast {
    struct MethodDecl : public FunctionNode {
        DECLARE_RTTI(MethodDecl, FunctionNode);
        AST_NODE_POD_CLONE(MethodDecl);

        using FunctionNode::FunctionNode;
    };

    struct TraitDecl
        : public Symbol
        , public ScopeTarget {
        DECLARE_RTTI(TraitDecl, Symbol);
        AST_NODE_POD_CLONE(TraitDecl);

        Vector<MethodDecl*> Methods;

        TraitDecl(const TypeName& trait)
            : Symbol(trait, trait.Name)
            , ScopeTarget(this) {}

        void addMethod(MethodDecl* method) override {
            Methods.emplace_back(method);
        }
    };

    struct TraitDef : public ExtensionDef {
        DECLARE_RTTI(TraitDef, ExtensionDef);
        AST_NODE_POD_CLONE(TraitDef);

        Resolvable<TraitDecl> Decl;

        TraitDef(const TypeName& traitDecl, const TypeName& structTarget)
            : ExtensionDef(structTarget)
            , Decl(traitDecl) {}
    };
} // namespace pepper::ast
