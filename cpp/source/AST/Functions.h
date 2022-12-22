//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include "AST/Param.h"
#include "Core/Common.h"
#include <vector>

namespace llvm {
    class Type;
    class Value;
} // namespace llvm

namespace pepper::ast {
    class FunctionNode : public Symbol {
        DECLARE_RTTI(FunctionNode, Node);

        Ref<Type> ReturnType;
        const Params Parameters;
        const bool Vararg;

      public:
        FunctionNode(Ref<Type> returnType, const std::string& name, const Params& params, bool vararg = false)
            : Symbol(name, TODO)
            , ReturnType(returnType)
            , Parameters(params)
            , Vararg(vararg) {
        }

        [[nodiscard]] Ref<Type> returnType() const {
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
        std::vector<Ref<Node>> Body;

      public:
        FunctionDef(Ref<Type> returnType, const std::string& name, const Params& params, bool varargs = false)
            : FunctionNode(std::move(returnType), name, params, varargs) {
        }

        std::vector<Ref<Node>>& body() {
            return Body;
        }

        const std::vector<Ref<Node>>& body() const {
            return Body;
        }
    };

    class MethodDef : public FunctionDef {
        DECLARE_RTTI(MethodDef, FunctionDef);

      private:
        Ref<StructDef> Struct;

      public:
        MethodDef(Ref<StructDef> strct,
                  Ref<Type> returnType,
                  const std::string& name,
                  const Params& params,
                  bool varargs = false)
            : FunctionDef(returnType, name, params, varargs)
            , Struct(strct) {
        }

        Ref<StructDef> structDef() const {
            return Struct;
        }
    };

    class ExternFunction : public FunctionDef {
        DECLARE_RTTI(ExternFunction, FunctionNode);

      public:
        ExternFunction(Ref<Type> returnType, const std::string& name, const Params& params, bool varargs = false)
            : FunctionNode(std::move(returnType), name, params, varargs) {
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

        llvm::Type* type() const override {
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
