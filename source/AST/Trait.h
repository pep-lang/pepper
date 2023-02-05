
#pragma once

#pragma once

#include "AST/Functions.h"

namespace pepper::ast {
    class MethodDecl : public FunctionNode {
        DECLARE_RTTI(MethodDecl, FunctionNode);
        AST_NODE_POD_CLONE(MethodDecl);

        using FunctionNode::FunctionNode;
    };

    class TraitDecl
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
} // namespace pepper::ast
