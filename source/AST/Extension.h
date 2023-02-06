
#pragma once

#include "AST/Method.h"

namespace pepper::ast {
    struct StructDef;

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
            : ExtensionDef(ext.Target) {
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
} // namespace pepper::ast