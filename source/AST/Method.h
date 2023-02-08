
#pragma once

#include "AST/Functions.h"

namespace pepper::ast {
    struct StructDef;

    struct ConstructorDef : public FunctionDef {
        DECLARE_RTTI(ConstructorDef, FunctionDef);
        AST_NODE_POD_CLONE(ConstructorDef);

        StructDef* Struct;

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

        void visit(Visitor& visitor) override;
        std::string signature() const override;
        std::string dump(int indent) const override;
    };

    struct MethodCall : public Expression {
        DECLARE_RTTI(MethodCall, Expression);
        AST_NODE_POD_CLONE(MethodCall);

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
            , This(m.This->cloneAs<Expression>())
            , Target(m.Target) {
            Args.clone(m.Args);
        }

        const TypeName& type() const override {
            return Target.value() ? Target->ReturnType : TypeName::Empty;
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(This);
            visitor.visit(Target);
            for (auto& arg : Args)
                visitor.visit(arg);
        }

        std::string toString() const override;
        std::string dump(int indent) const override;
    };
} // namespace pepper::ast
