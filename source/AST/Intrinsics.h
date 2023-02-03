//
// Created by Justin Boswell on 12/29/22.
//

#pragma once

#include "AST/Node.h"
#include "Core/Query.h"

namespace pepper::ast {
    struct Intrinsic : public Expression {
        DECLARE_RTTI(Intrinsic, Expression);
        AST_NODE_POD_CLONE(Intrinsic)

        TypeName Target;
        Vector<TNodeRef<Expression>> Args;

        Intrinsic(const TypeName& target, const Vector<TNodeRef<Expression>>& args = {})
            : Target(target)
            , Args(args) {}

        Intrinsic(const Intrinsic&) = default;
        Intrinsic(Intrinsic&&) = default;
        Intrinsic& operator=(const Intrinsic&) = default;

        std::string toString() const override {
            return llvm::formatv("{0}: {1}", Node::toString(), Target.toString());
        }

        std::string dump(int indent) const override {
            auto args = llvm::join(Query(Args).select<std::string>([](auto& a) { return a->dump(); }), ", ");
            return llvm::formatv("{0}: {1}({2})", Node::dump(indent), Target.toString(), args);
        }

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            visitor.visit(Target);
            for (auto& arg : Args) {
                visitor.visit(arg);
            }
        }
    };

    struct SizeOf : public Intrinsic {
        DECLARE_RTTI(SizeOf, Intrinsic);
        AST_NODE_POD_CLONE(SizeOf);
        using Intrinsic::Intrinsic;
    };

    struct ArrayIndex : public Intrinsic {
        DECLARE_RTTI(ArrayIndex, Intrinsic);
        AST_NODE_POD_CLONE(ArrayIndex);
        using Intrinsic::Intrinsic;
    };

    struct IsPod : public Intrinsic {
        DECLARE_RTTI(IsPod, Intrinsic);
        AST_NODE_POD_CLONE(IsPod);
        using Intrinsic::Intrinsic;
    };

    struct Default : public Intrinsic {
        DECLARE_RTTI(Default, Intrinsic);
        AST_NODE_POD_CLONE(Default);
        using Intrinsic::Intrinsic;
    };
} // namespace pepper::ast
