
#pragma once

#include "Sema/Model/Method.h"

namespace pepper::sema {
    struct StructDef;

    struct ExtensionDef
        : public Node
        , public ScopeTarget {
        DECLARE_RTTI(ExtensionDef, Node);
        SEMA_NODE_POD_CLONE(ExtensionDef);

        Resolvable<StructDef> Target;
        NodeList<MethodDef> method_members;

        ExtensionDef(const TypeName& target = {})
            : ScopeTarget(this)
            , Target(target) {}

        ExtensionDef(const ExtensionDef& ext)
            : ExtensionDef(ext.Target) {
            method_members.clone(ext.method_members);
        }

        void add_function(FunctionDef* function) override {
            if (auto method = function->as<MethodDef>())
                method_members.emplace_back(method);
            // TODO: static functions
        }

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            visitor.visit(Target);
            for (auto& method : method_members)
                visitor.visit(method);
        }

        std::string to_string() const override;
        std::string dump(int indent) const override;
    };
} // namespace pepper::sema
