//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <utility>

#include "AST/Branches.h"
#include "AST/Node.h"
#include "AST/Param.h"
#include "AST/Variables.h"
#include "Core/Common.h"
#include "Core/Query.h"
#include "Core/String.h"
#include "Core/Vector.h"

namespace pepper::ast {
    struct FunctionNode
        : public Symbol
        , public ScopeTarget {
        DECLARE_RTTI(FunctionNode, Node);

        TypeName ReturnType;
        Params Parameters;
        const bool Vararg;
        bool Generic;

        FunctionNode(const TypeName& returnType, const TypeName& name, const Params& params, bool vararg = false);

        std::string toString() const override;
        std::string dump(int indent) const override;

        bool isGeneric() const;

        virtual std::string signature() const;

        void visit(Visitor& visitor) override {
            Symbol::visit(visitor);
            visitor.visit(ReturnType);
            for (auto& param : Parameters)
                visitor.visit(param.Type);
        }
    };

    struct FunctionDef : public FunctionNode {
        DECLARE_RTTI(FunctionDef, FunctionNode);

        TNodeRef<Block> Body;

        FunctionDef(
            const TypeName& returnType, const TypeName& name, const Params& params = Params(), bool varargs = false)
            : FunctionNode(returnType, name, params, varargs) {
            Body.reset(new Block(name));
        }

        Node* clone() const override;

        std::string toString() const override {
            const char* sep = "\n";
            auto contents = llvm::join_items(sep, FunctionNode::toString(), Body->toString());
            return contents;
        }

        std::string dump(int indent) const override;

        void visit(Visitor& visitor) override {
            FunctionNode::visit(visitor);
            visitor.visit(Body);
        }
    };

    struct FunctionSpec : public Symbol {
        DECLARE_RTTI(FunctionSpec, Symbol);
        AST_NODE_POD_CLONE(FunctionSpec);

        FunctionSpec(const TypeName& spec)
            : Symbol(spec, spec.toString()) {}

        std::string toString() const override {
            return llvm::formatv("{0} {1}", Symbol::toString(), Name);
        }

        std::string dump(int) const override {
            return toString();
        }
    };

    struct ExternFunctionDef : public FunctionNode {
        DECLARE_RTTI(ExternFunctionDef, FunctionNode);
        AST_NODE_POD_CLONE(ExternFunctionDef);

        bool Weak = false;

        ExternFunctionDef(
            const TypeName& returnType, const Ident& name, const Params& params = {}, bool varargs = false)
            : FunctionNode(returnType, name, params, varargs) {}
    };

    struct FunctionCall : public Expression {
        DECLARE_RTTI(FunctionCall, Expression);
        AST_NODE_POD_CLONE(FunctionCall);

        Resolvable<FunctionDef> Target;
        ExprList Args;

        FunctionCall(const TypeName& target, ExprList&& args = {})
            : Target(target)
            , Args(std::move(args)) {}

        FunctionCall(const FunctionCall& call)
            : Target(call.Target) {
            Args.clone(call.Args);
        }

        const TypeName& type() const override {
            return Target->ReturnType;
        }

        std::string toString() const override;
        std::string dump(int indent) const override;
        void visit(Visitor& visitor) override;
    };

    struct Return : public Expression {
        DECLARE_RTTI(Return, Expression);
        AST_NODE_POD_CLONE(Return);

        TypeName Type;
        TNodeRef<Expression> Value;

        Return(TypeName type = {"void"}, Expression* value = nullptr)
            : Type(std::move(type))
            , Value(value) {}

        const TypeName& type() const override {
            return Type;
        }

        std::string toString() const override {
            return llvm::formatv("{0} {1}", Node::toString(), Value ? Value->toString() : "void");
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), Value ? Value->dump() : "void");
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            visitor.visit(Type);
            if (Value)
                visitor.visit(Value);
        }
    };
} // namespace pepper::ast
