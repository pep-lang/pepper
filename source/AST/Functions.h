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
    struct FunctionNode : public Symbol {
        DECLARE_RTTI(FunctionNode, Node);

        TypeName ReturnType;
        Params Parameters;
        const bool Vararg;

        FunctionNode(const TypeName& returnType, const Ident& name, const Params& params, bool vararg = false);

        std::string toString() const override;
        std::string dump(int indent) const override;

        void specialize(const Specialization& spec) override;
    };

    struct FunctionDef : public FunctionNode {
        DECLARE_RTTI(FunctionDef, FunctionNode);
        AST_NODE_POD_CLONE(FunctionDef);

        Ref<Block> Body;

        FunctionDef(
            const TypeName& returnType, const Ident& name, const Params& params = Params(), bool varargs = false)
            : FunctionNode(returnType, name, params, varargs) {
            Body = Ref<Block>::New(name);
        }

        std::string toString() const override {
            const char* sep = "\n";
            auto contents = llvm::join_items(sep, FunctionNode::toString(), Body->toString());
            return contents;
        }

        std::string dump(int indent) const override;

        void specialize(const Specialization& spec) override;
    };

    struct ExternFunctionDef : public FunctionDef {
        DECLARE_RTTI(ExternFunctionDef, FunctionDef);
        AST_NODE_POD_CLONE(ExternFunctionDef);

        ExternFunctionDef(
            const TypeName& returnType, const Ident& name, const Params& params = Params(), bool varargs = false)
            : FunctionDef(returnType, name, params, varargs) {
        }

        static Ref<ExternFunctionDef> Malloc;
        static Ref<ExternFunctionDef> Free;
    };

    struct FunctionCall : public Expression {
        DECLARE_RTTI(FunctionCall, Expression);
        AST_NODE_POD_CLONE(FunctionCall);

        Ref<FunctionDef> Target;
        const Vector<Ref<Expression>> Args;

        FunctionCall(Ref<FunctionDef> target, const Vector<Ref<Expression>>& args = {})
            : Target(std::move(target))
            , Args(args) {
        }

        const TypeName& type() const override {
            return Target->ReturnType;
        }

        std::string toString() const override {
            Vector<std::string> argsStr = Query(Args).select<std::string>([](auto a) { return a->toString(); });
            return trim(
                Node::toString() +
                std::string(llvm::formatv("{0}({1})", Target->Name, llvm::join(argsStr.begin(), argsStr.end(), ", "))));
        }

        std::string dump(int indent) const override {
            Vector<std::string> argsStr = Query(Args).select<std::string>([](auto a) { return a->dump(); });
            return

                       llvm::formatv("{0} {1}({2})", Node::dump(indent), Target->Name, llvm::join(argsStr.begin(), argsStr.end(), ", "));
        }
    };

    struct Return : public Expression {
        DECLARE_RTTI(Return, Expression);
        AST_NODE_POD_CLONE(Return);

        TypeName Type;
        Ref<Expression> Value;

        Return(TypeName type = {"void"}, Ref<Expression> value = nullptr)
            : Type(std::move(type))
            , Value(std::move(value)) {
        }

        const TypeName& type() const override {
            return Type;
        }

        std::string toString() const override {
            return llvm::formatv("{0} {1}", Node::toString(), Value ? Value->toString() : "void");
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), Value ? Value->dump() : "void");
        }

        void specialize(const Specialization& spec) override;
    };
} // namespace pepper::ast
