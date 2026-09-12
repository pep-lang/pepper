
#pragma once

#include "Sema/Model/Extension.h"

namespace pepper::sema {
    struct MethodDecl : public FunctionNode {
        DECLARE_RTTI(MethodDecl, FunctionNode);
        SEMA_NODE_POD_CLONE(MethodDecl);

        using FunctionNode::FunctionNode;
    };

    struct TraitDecl
        : public Symbol
        , public ScopeTarget {
        DECLARE_RTTI(TraitDecl, Symbol);
        SEMA_NODE_POD_CLONE(TraitDecl);

        Vector<MethodDecl*> method_members;

        TraitDecl(const TypeName& trait)
            : Symbol(trait, trait.name)
            , ScopeTarget(this) {}

        void add_method(MethodDecl* method) override {
            method_members.emplace_back(method);
        }
    };

    struct TraitDef : public ExtensionDef {
        DECLARE_RTTI(TraitDef, ExtensionDef);
        SEMA_NODE_POD_CLONE(TraitDef);

        Resolvable<TraitDecl> decl;

        TraitDef(const TypeName& traitDecl, const TypeName& structTarget)
            : ExtensionDef(structTarget)
            , decl(traitDecl) {}
    };
} // namespace pepper::sema
