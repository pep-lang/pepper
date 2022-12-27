//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <utility>

#include "AST/Node.h"
#include "AST/Param.h"
#include "AST/Struct.h"
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
            return Node::toString() +
                   std::string(llvm::formatv(
                       "{0} {1}({2})", ReturnType, identifier(), llvm::join(types.begin(), types.end(), ", ")));
        }
    };

    class FunctionDef : public FunctionNode {
        DECLARE_RTTI(FunctionDef, FunctionNode);

      private:
        Vector<Ref<VariableDef>> Locals;
        Vector<Ref<Expression>> Body;

      public:
        FunctionDef(const Name& returnType, const Name& name, const Params& params = Params(), bool varargs = false)
            : FunctionNode(returnType, name, params, varargs) {
        }

        Vector<Ref<VariableDef>>& locals() {
            return Locals;
        }

        const Vector<Ref<VariableDef>>& locals() const {
            return Locals;
        }

        Vector<Ref<Expression>>& body() {
            return Body;
        }

        [[nodiscard]] const Vector<Ref<Expression>>& body() const {
            return Body;
        }

        std::string toString() const override {
            const char* sep = "\n  ";
            Vector<std::string> vars = Query(Locals).select<std::string>([](auto l) { return l->toString(); });
            Vector<std::string> exprs = Query(Body).select<std::string>([](auto e) { return e->toString(); });
            auto contents = rtrim(llvm::join_items(sep,
                                                   FunctionNode::toString(),
                                                   llvm::join(vars.begin(), vars.end(), sep),
                                                   llvm::join(exprs.begin(), exprs.end(), sep)));
            return contents;
        }
    };

    class MethodDef : public FunctionDef {
        DECLARE_RTTI(MethodDef, FunctionDef);

      private:
        Ref<StructDef> Struct;

      public:
        MethodDef(Ref<StructDef> strct,
                  const Name& returnType,
                  const Name& name,
                  const Params& params = Params(),
                  bool varargs = false)
            : FunctionDef(returnType, name, params, varargs)
            , Struct(std::move(strct)) {
        }

        [[nodiscard]] Ref<StructDef> structDef() const {
            return Struct;
        }

        virtual std::string toString() const override {
            const char* sep = "\n    ";
            Vector<std::string> types = Query(Parameters).select<std::string>([](auto p) { return p.Type; });
            Vector<std::string> vars = Query(locals()).select<std::string>([](auto l) { return l->toString(); });
            Vector<std::string> exprs = Query(body()).select<std::string>([](auto e) { return e->toString(); });
            return Node::toString() +
                   std::string(llvm::formatv("{0} {1}.{2}({3})",
                                             ReturnType,
                                             structDef()->identifier(),
                                             identifier(),
                                             llvm::join(types.begin(), types.end(), ", "))) +
                   sep + llvm::join(vars.begin(), vars.end(), sep) + sep + llvm::join(exprs.begin(), exprs.end(), sep);
            ;
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
    };

    class FunctionEnd : public Node {
        DECLARE_RTTI(FunctionEnd, Node);
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
            return Node::toString() + std::string(llvm::formatv("{0}", Value ? Value->toString() : "void"));
        }
    };
} // namespace pepper::ast
