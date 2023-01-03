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

        std::string toString() const override {
            Vector<std::string> types = Query(Parameters).select<std::string>([](auto p) { return p.Type.toString(); });
            std::string sig = llvm::formatv(
                "{0} {1} {2}({3})", Node::toString(), ReturnType, Name, llvm::join(types.begin(), types.end(), ", "));
            return sig;
        }

        std::string dump(int indent) const override {
            Vector<std::string> types =
                Query(Parameters).select<std::string>([](auto p) { return p.Type.toString() + " " + p.Name; });
            return llvm::formatv("{0} {1} {2}({3})",
                                 Node::dump(indent),
                                 ReturnType.toString(),
                                 Name,
                                 llvm::join(types.begin(), types.end(), ", "));
        }
    };

    struct FunctionDef : public FunctionNode {
        DECLARE_RTTI(FunctionDef, FunctionNode);

        Ref<Block> Body;

        FunctionDef(
            const TypeName& returnType, const Ident& name, const Params& params = Params(), bool varargs = false)
            : FunctionNode(returnType, name, params, varargs) {
            Body = Ref<Block>::New(nullptr, name);
        }

        std::string toString() const override {
            const char* sep = "\n";
            auto contents = llvm::join_items(sep, FunctionNode::toString(), Body->toString());
            return contents;
        }

        std::string dump(int indent = 0) const override {
            const char* sep = "\n  ";
            auto contents = llvm::join_items(sep, FunctionNode::dump(indent), Body->dump(indent));
            return contents;
        }
    };

    struct ExternFunctionDef : public FunctionDef {
        DECLARE_RTTI(ExternFunctionDef, FunctionDef);

        ExternFunctionDef(
            const TypeName& returnType, const Ident& name, const Params& params = Params(), bool varargs = false)
            : FunctionDef(returnType, name, params, varargs) {
        }

        static Ref<ExternFunctionDef> Malloc;
        static Ref<ExternFunctionDef> Free;
    };

    struct FunctionCall : public Expression {
        DECLARE_RTTI(FunctionCall, Expression);

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
            Vector<std::string> argsStr = Query(Args).select<std::string>([indent](auto a) { return a->dump(indent); });
            return trim(
                Node::dump() +
                std::string(llvm::formatv("{0}({1})", Target->Name, llvm::join(argsStr.begin(), argsStr.end(), ", "))));
        }
    };

    struct Return : public Expression {
        DECLARE_RTTI(Return, Expression);

        Ref<FunctionDef> Target;
        Ref<Expression> Value;

        Return(Ref<FunctionDef> target, Ref<Expression> value = nullptr)
            : Target(std::move(target))
            , Value(std::move(value)) {
        }

        const TypeName& type() const override {
            return Target->ReturnType;
        }

        std::string toString() const override {
            return llvm::formatv("{0} {1}", Node::toString(), Value ? Value->toString() : "void");
        }

        std::string dump(int indent) const override {
            return llvm::formatv("{0} {1}", Node::dump(indent), Value ? Value->dump() : "void");
        }
    };
} // namespace pepper::ast
