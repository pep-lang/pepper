

#pragma once

#include <string>
#include <utility>

#include "Block.h"
#include "Core/Ident.h"
#include "Core/RTTI.h"
#include "Sema/Model/Node.h"
#include "Sema/Model/Param.h"
#include "Sema/Model/Resolvable.h"
#include "Sema/Model/TypeName.h"
#include "Variables.h"
#include "Visitor.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper::sema {
    struct FunctionNode
        : public Symbol
        , public ScopeTarget {
        DECLARE_RTTI(FunctionNode, Node);

        enum class StorageClassType {
            Default = 0,
            Static = 1,
        };

        TypeName return_type;
        Params parameters;

        StorageClassType storage_class = StorageClassType::Default;
        const bool is_vararg;
        bool is_generic_func;

        FunctionNode(const TypeName& return_type, const TypeName& name, const Params& params, bool vararg = false);

        std::string to_string() const override;
        std::string dump(int indent) const override;

        bool is_generic() const;

        bool is_static() const {
            return storage_class == StorageClassType::Static;
        }

        virtual std::string signature() const;

        void visit(Visitor& visitor) override {
            Symbol::visit(visitor);
            visitor.visit(return_type);
            for (auto& param : parameters) {
                visitor.visit(param.type);
                if (param.default_value) {
                    visitor.visit(param.default_value);
                }
            }
        }
    };

    struct FunctionDef : public FunctionNode {
        DECLARE_RTTI(FunctionDef, FunctionNode);

        TNodeRef<Block> body;

        FunctionDef(const TypeName& return_type = {},
                    const TypeName& name = {},
                    const Params& params = {},
                    bool varargs = false)
            : FunctionNode(return_type, name, params, varargs) {
            body.reset(new Block(name));
        }

        Node* clone() const override;

        std::string dump(int indent) const override;

        void visit(Visitor& visitor) override {
            FunctionNode::visit(visitor);
            visitor.visit(body);
        }
    };

    struct FunctionSpec : public Symbol {
        DECLARE_RTTI(FunctionSpec, Symbol);
        SEMA_NODE_POD_CLONE(FunctionSpec);

        FunctionSpec(const TypeName& spec)
            : Symbol(spec, spec.to_string()) {}

        std::string to_string() const override {
            return llvm::formatv("{0}: {1}", node_name(), name);
        }

        std::string dump(int) const override {
            return to_string();
        }
    };

    struct ExternFunctionRef : public FunctionNode {
        DECLARE_RTTI(ExternFunctionRef, FunctionNode);
        SEMA_NODE_POD_CLONE(ExternFunctionRef);

        bool is_weak = false;

        ExternFunctionRef(
            const TypeName& return_type, const Ident& name, const Params& params = {}, bool varargs = false)
            : FunctionNode(return_type, name, params, varargs) {}
    };

    struct FunctionCall : public Expression {
        DECLARE_RTTI(FunctionCall, Expression);
        SEMA_NODE_POD_CLONE(FunctionCall);

        Expression* function = nullptr;
        // DEPRECATED, use the expression form
        Resolvable<FunctionNode> target;
        ExprList args;

        FunctionCall(const TypeName& target, ExprList&& args = {})
            : target(target)
            , args(std::move(args)) {}

        FunctionCall(Expression* func, ExprList&& args = {})
            : function(func)
            , args(std::move(args)) {
            // SHIM until target is fully removed
            if (const auto* symbol = func->as<sema::SymbolRef>()) {
                target = Resolvable<FunctionNode>{symbol->id};
            }
        }

        FunctionCall(const FunctionCall& call)
            : FunctionCall(call.target, call.args.clone()) {}

        const TypeName& type() const override {
            return target.value() ? target->return_type : Expression::type();
        }

        std::string to_string() const override;
        std::string dump(int indent) const override;
        void visit(Visitor& visitor) override;
    };

    struct Return : public Expression {
        DECLARE_RTTI(Return, Expression);
        SEMA_NODE_POD_CLONE(Return);

        TNodeRef<Expression> expr;

        Return(Expression* value = nullptr)
            : expr(value) {}

        const TypeName& type() const override {
            return expr ? expr->type() : TypeName::Void;
        }

        std::string to_string() const override {
            return llvm::formatv("{0}: {1}", node_name(), expr ? expr->to_string() : "void");
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), expr ? expr->dump() : "void");
        }

        void visit(Visitor& visitor) override {
            Expression::visit(visitor);
            if (expr)
                visitor.visit(expr);
        }
    };
} // namespace pepper::sema
