
#pragma once

#include "Sema/Model/Functions.h"

namespace pepper::sema {
    struct StructDef;

    struct ConstructorDef : public FunctionDef {
        DECLARE_RTTI(ConstructorDef, FunctionDef);
        SEMA_NODE_POD_CLONE(ConstructorDef);

        StructDef* Struct;

        ConstructorDef(class StructDef* st,
                       const TypeName& return_type,
                       const TypeName& name,
                       const Params& params = Params(),
                       bool varargs = false)
            : FunctionDef(return_type, name, params, varargs)
            , Struct(st) {}
    };

    struct MethodDef : public FunctionDef {
        DECLARE_RTTI(MethodDef, FunctionDef);

        Resolvable<StructDef> parent;

      public:
        MethodDef(const TypeName& structName,
                  const TypeName& return_type = {},
                  const TypeName& name = {},
                  const Params& params = Params(),
                  bool vararg = false);

        Node* clone() const override;

        void visit(Visitor& visitor) override;
        std::string signature() const override;
        std::string dump(int indent) const override;
    };

    struct MethodCall : public Expression {
        DECLARE_RTTI(MethodCall, Expression);
        SEMA_NODE_POD_CLONE(MethodCall);

        TNodeRef<Expression> This;
        Resolvable<MethodDef> Target;
        ExprList Args;

        MethodCall(Expression* thisRef, const TypeName& methodName, const ExprList& args = {})
            : This(thisRef)
            , Target(methodName) {
            Args.clone(args);
        }

        MethodCall(const MethodCall& m)
            : Expression(m)
            , This(m.This->clone_as<Expression>())
            , Target(m.Target) {
            Args.clone(m.Args);
        }

        const TypeName& type() const override {
            return Target.value() ? Target->return_type : TypeName::Auto;
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(This);
            visitor.visit(Target);
            for (auto& arg : Args)
                visitor.visit(arg);
        }

        std::string to_string() const override;
        std::string dump(int indent) const override;
    };
} // namespace pepper::sema
