
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

        std::string signature() const override;
        std::string toString() const override;
        std::string dump(int indent) const override;
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
} // namespace pepper::ast
