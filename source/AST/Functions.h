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
    class StructDef;
    class VariableDef;

    class FunctionNode : public Symbol {
        DECLARE_RTTI(FunctionNode, Node);

        Name ReturnType;
        Params Parameters;
        const bool Vararg;

      public:
        FunctionNode(const Name& returnType, const Name& name, const Params& params, bool vararg = false);

        [[nodiscard]] const Name& returnType() const {
            return ReturnType;
        }

        void setReturnType(const Name& newReturnType) {
            ReturnType = newReturnType;
        }

        [[nodiscard]] const Params& params() const {
            return Parameters;
        }

        [[nodiscard]] Params& params() {
            return Parameters;
        }

        [[nodiscard]] bool isVararg() const {
            return Vararg;
        }

        virtual std::string toString() const override {
            Vector<std::string> types = Query(Parameters).select<std::string>([](auto p) { return p.Type; });
            return llvm::formatv("{0} {1} {2}({3})",
                                 Node::toString(),
                                 ReturnType,
                                 identifier(),
                                 llvm::join(types.begin(), types.end(), ", "));
        }

        virtual std::string dump() const override {
            Vector<std::string> types = Query(Parameters).select<std::string>([](auto p) { return p.Type; });
            return llvm::formatv("{0} {1} {2}({3})",
                                 Node::dump(),
                                 ReturnType,
                                 identifier(),
                                 llvm::join(types.begin(), types.end(), ", "));
        }
    };

    class FunctionDef : public FunctionNode {
        DECLARE_RTTI(FunctionDef, FunctionNode);

      private:
        Vector<Ref<VariableDef>> Locals;
        Ref<Block> Body;

      public:
        FunctionDef(const Name& returnType, const Name& name, const Params& params = Params(), bool varargs = false)
            : FunctionNode(returnType, name, params, varargs) {
            Body = Ref<Block>::New(nullptr, name);
        }

        Ref<Block>& body() {
            return Body;
        }

        [[nodiscard]] const Ref<Block>& body() const {
            return Body;
        }

        std::string toString() const override {
            const char* sep = "\n";
            Vector<std::string> vars = Query(Locals).select<std::string>([](auto l) { return l->toString(); });
            Vector<std::string> exprs = Query(Body->Items).select<std::string>([](auto e) { return e->toString(); });
            auto contents = rtrim(llvm::join_items(sep,
                                                   FunctionNode::toString(),
                                                   llvm::join(vars.begin(), vars.end(), sep),
                                                   llvm::join(exprs.begin(), exprs.end(), sep)));
            return contents;
        }

        std::string dump() const override {
            const char* sep = "\n  ";
            Vector<std::string> vars = Query(Locals).select<std::string>([](auto l) { return l->dump(); });
            Vector<std::string> exprs = Query(Body->Items).select<std::string>([](auto e) { return e->dump(); });
            auto contents = rtrim(llvm::join_items(sep,
                                                   FunctionNode::dump(),
                                                   llvm::join(vars.begin(), vars.end(), sep),
                                                   llvm::join(exprs.begin(), exprs.end(), sep)));
            return contents;
        }
    };

    class ExternFunctionDef : public FunctionDef {
        DECLARE_RTTI(ExternFunctionDef, FunctionDef);

      public:
        ExternFunctionDef(
            const Name& returnType, const Name& name, const Params& params = Params(), bool varargs = false)
            : FunctionDef(returnType, name, params, varargs) {
        }

        static Ref<ExternFunctionDef> Malloc;
        static Ref<ExternFunctionDef> Free;
    };

    class FunctionCall : public Expression {
        DECLARE_RTTI(FunctionCall, Expression);
        Ref<FunctionDef> Target;
        const Vector<Ref<Expression>> Args;

      public:
        FunctionCall(Ref<FunctionDef> target, const Vector<Ref<Expression>>& args = {})
            : Target(target)
            , Args(args) {
        }

        Ref<FunctionDef> target() const {
            return Target;
        }

        const Vector<Ref<Expression>>& args() const {
            return Args;
        }

        const Name& type() const override {
            return Target->returnType();
        }

        std::string toString() const override {
            Vector<std::string> argsStr = Query(args()).select<std::string>([](auto a) { return a->toString(); });
            return trim(Node::toString() +
                        std::string(llvm::formatv(
                            "{0}({1})", Target->identifier(), llvm::join(argsStr.begin(), argsStr.end(), ", "))));
        }

        std::string dump() const override {
            Vector<std::string> argsStr = Query(args()).select<std::string>([](auto a) { return a->dump(); });
            return trim(Node::dump() +
                        std::string(llvm::formatv(
                            "{0}({1})", Target->identifier(), llvm::join(argsStr.begin(), argsStr.end(), ", "))));
        }
    };

    class Return : public Expression {
        DECLARE_RTTI(Return, Expression);

      private:
        Ref<FunctionDef> Target;
        Ref<Expression> Value;

      public:
        Return(Ref<FunctionDef> target, Ref<Expression> value = nullptr)
            : Target(target)
            , Value(value) {
        }

        const Name& type() const override {
            return Target->returnType();
        }

        Ref<Expression> value() const {
            return Value;
        }

        void setValue(Ref<Expression> value) {
            Value = value;
        }

        Ref<FunctionDef> target() const {
            return Target;
        }

        std::string toString() const override {
            return llvm::formatv("{0} {1}", Node::toString(), Value ? Value->toString() : "void");
        }

        std::string dump() const override {
            return llvm::formatv("{0} {1}", Node::dump(), Value ? Value->dump() : "void");
        }
    };
} // namespace pepper::ast
