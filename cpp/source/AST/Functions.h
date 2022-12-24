//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include "AST/Node.h"
#include "AST/Param.h"
#include "Core/Common.h"
#include <utility>
#include <vector>

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
        std::vector<Ref<VariableDef>> Locals;
        std::vector<Ref<Node>> Body;

      public:
        FunctionDef(const Name& returnType, const Name& name, const Params& params, bool varargs = false)
            : FunctionNode(returnType, name, params, varargs) {
        }

        std::vector<Ref<Node>>& body() {
            return Body;
        }

        [[nodiscard]] const std::vector<Ref<Node>>& body() const {
            return Body;
        }

        std::vector<Ref<VariableDef>>& locals() {
            return Locals;
        }

        const std::vector<Ref<VariableDef>>& locals() const {
            return Locals;
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
                  const Params& params,
                  bool varargs = false)
            : FunctionDef(returnType, name, params, varargs)
            , Struct(std::move(strct)) {
        }

        [[nodiscard]] Ref<StructDef> structDef() const {
            return Struct;
        }
    };

    class ExternFunctionDef : public FunctionDef {
        DECLARE_RTTI(ExternFunctionDef, FunctionNode);

      public:
        ExternFunctionDef(const Name& returnType, const Name& name, const Params& params, bool varargs = false)
            : FunctionDef(returnType, name, params, varargs) {
        }
    };

    class FunctionCall : public Expression {
        DECLARE_RTTI(FunctionCall, Expression);
        Ref<FunctionDef> Target;
        const std::vector<Ref<Expression>>& Args;

      public:
        FunctionCall(Ref<FunctionDef> target, const std::vector<Ref<Expression>>& args)
            : Target(target)
            , Args(args) {
        }

        Ref<FunctionDef> target() const {
            return Target;
        }

        const std::vector<Ref<Expression>>& args() const {
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
