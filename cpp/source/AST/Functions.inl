//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

namespace pepper::ast {
    class FunctionNode : public Symbol {
        DECLARE_RTTI(FunctionNode, Node);

        Ref<Type> ReturnType;
        const std::vector<Symbol> Params;
        const bool Vararg;

      public:
        FunctionNode(Ref<Type> returnType,
                     const std::string& name,
                     const std::vector<Symbol>& params,
                     bool vararg = false);

        [[nodiscard]] Ref<Type> returnType() const {
            return ReturnType;
        }

        [[nodiscard]] const std::vector<Symbol>& params() const {
            return Params;
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
        FunctionDef(Ref<Type> returnType,
                    const std::string& name,
                    const std::vector<Symbol>& params,
                    bool varargs = false)
            : FunctionNode(std::move(returnType), name, params, varargs) {
        }
    };

    class ExternFunction : public FunctionNode {
        DECLARE_RTTI(ExternFunction, FunctionNode);

      public:
        ExternFunction(Ref<Type> returnType,
                       const std::string& name,
                       const std::vector<Symbol>& params,
                       bool varargs = false)
            : FunctionNode(std::move(returnType), name, params, varargs) {
        }
    };

    class FunctionCall : public Expression {
        DECLARE_RTTI(FunctionCall, Expression);
        Ref<FunctionDef> Target;
        const std::vector<Ref<Expression>>& Args;

      public:
        FunctionCall(Ref<FunctionDef> target, const std::vector<Ref<Expression>>& args);
    };
}
