

#pragma once

#include <utility>

#include "AST/Branches.h"
#include "AST/Node.h"
#include "AST/Param.h"
#include "AST/Resolvable.h"
#include "AST/Variables.h"
#include "Core/Query.h"
#include "Core/String.h"
#include "Core/Vector.h"

namespace pepper::ast {
    struct FunctionNode
        : public Symbol
        , public ScopeTarget {
        DECLARE_RTTI(FunctionNode, Node);

        enum class StorageClassType {
            Default = 0,
            Static = 1,
        };

        TypeName ReturnType;
        Params Parameters;

        StorageClassType StorageClass = StorageClassType::Default;
        const bool Vararg;
        bool Generic;

        FunctionNode(const TypeName& returnType, const TypeName& name, const Params& params, bool vararg = false);

        std::string toString() const override;
        std::string dump(int indent) const override;

        bool isGeneric() const;

        bool isStatic() const {
            return StorageClass == StorageClassType::Static;
        }

        virtual std::string signature() const;

        void visit(Visitor& visitor) override {
            Symbol::visit(visitor);
            visitor.visit(ReturnType);
            for (auto& param : Parameters) {
                visitor.visit(param.Type);
                if (param.Default) {
                    visitor.visit(param.Default);
                }
            }
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
            return llvm::formatv("{0}: {1}", nodeName(), Name);
        }

        std::string dump(int) const override {
            return toString();
        }
    };

    struct ExternFunctionRef : public FunctionNode {
        DECLARE_RTTI(ExternFunctionRef, FunctionNode);
        AST_NODE_POD_CLONE(ExternFunctionRef);

        bool Weak = false;

        ExternFunctionRef(
            const TypeName& returnType, const Ident& name, const Params& params = {}, bool varargs = false)
            : FunctionNode(returnType, name, params, varargs) {}
    };

    struct FunctionCall : public Expression {
        DECLARE_RTTI(FunctionCall, Expression);
        AST_NODE_POD_CLONE(FunctionCall);

        Resolvable<FunctionNode> Target;
        ExprList Args;

        FunctionCall(const TypeName& target, ExprList&& args = {})
            : Target(target)
            , Args(std::move(args)) {}

        FunctionCall(const FunctionCall& call)
            : FunctionCall(call.Target, call.Args.clone()) {}

        const TypeName& type() const override {
            return Target.value() ? Target->ReturnType : Expression::type();
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
            return llvm::formatv("{0}: {1}", nodeName(), Value ? Value->toString() : "void");
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
