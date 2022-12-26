//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <utility>

#include "AST/Node.h"
#include "AST/Param.h"
#include "Core/Common.h"
#include "Core/Vector.h"

namespace pepper::ast {
    class StructDef;
    class VariableDef;

    class FunctionNode : public Symbol {
        DECLARE_RTTI(FunctionNode, Node);

        Name ReturnType;
        const Params Parameters;
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

        [[nodiscard]] bool isVararg() const {
            return Vararg;
        }
    };

    class FunctionDef : public FunctionNode {
        DECLARE_RTTI(FunctionDef, FunctionNode);

      private:
        Vector<Ref<VariableDef>> Locals;
        Vector<Ref<Expression>> Inits;
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

        Vector<Ref<Expression>>& inits() {
            return Inits;
        }

        const Vector<Ref<Expression>>& inits() const {
            return Inits;
        }

        Vector<Ref<Expression>>& body() {
            return Body;
        }

        [[nodiscard]] const Vector<Ref<Expression>>& body() const {
            return Body;
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

        Ref<FunctionDef> target() const {
            return Target;
        }
    };
} // namespace pepper::ast
