

#pragma once

#include "Sema/Model/Node.h"
#include "Sema/Model/Visitor.h"
#include "Core/Query.h"

namespace pepper::sema {
    struct Intrinsic : public Expression {
        DECLARE_RTTI(Intrinsic, Expression);
        SEMA_NODE_POD_CLONE(Intrinsic)

        TypeName target;
        Vector<TNodeRef<Expression>> args;

        Intrinsic(const TypeName& target, const Vector<TNodeRef<Expression>>& args = {})
            : target(target)
            , args(args) {}

        Intrinsic(const Intrinsic&) = default;
        Intrinsic(Intrinsic&&) = default;
        Intrinsic& operator=(const Intrinsic&) = default;

        std::string to_string() const override {
            return llvm::formatv("{0}: {1}", node_name(), target.to_string());
        }

        std::string dump(int indent) const override {
            auto args_dump = llvm::join(Query(args).select<std::string>([](auto& a) { return a->dump(); }), ", ");
            return llvm::formatv("{0}: {1}({2})", Node::dump(indent), target.to_string(), args_dump);
        }

        void visit(Visitor& visitor) override {
            Node::visit(visitor);
            visitor.visit(target);
            for (auto& arg : args) {
                visitor.visit(arg);
            }
        }
    };

    struct SizeOf : public Intrinsic {
        DECLARE_RTTI(SizeOf, Intrinsic);
        SEMA_NODE_POD_CLONE(SizeOf);
        using Intrinsic::Intrinsic;
    };

    struct ArrayIndex : public Intrinsic {
        DECLARE_RTTI(ArrayIndex, Intrinsic);
        SEMA_NODE_POD_CLONE(ArrayIndex);
        using Intrinsic::Intrinsic;
    };

    struct IsPod : public Intrinsic {
        DECLARE_RTTI(IsPod, Intrinsic);
        SEMA_NODE_POD_CLONE(IsPod);
        using Intrinsic::Intrinsic;
    };

    struct Default : public Intrinsic {
        DECLARE_RTTI(Default, Intrinsic);
        SEMA_NODE_POD_CLONE(Default);
        using Intrinsic::Intrinsic;
    };
} // namespace pepper::sema
