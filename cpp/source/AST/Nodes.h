#pragma once

#include "Core/Common.h"
#include "Core/RTTI.h"
#include <string>
#include <vector>

namespace pepper {
    class Type;
    class Value;
    class Function;
    class Symbol;
} // namespace pepper

namespace pepper::ast {

    class Node {
        DECLARE_RTTI(Node);

      public:
        Node() = default;
        virtual ~Node() = default;
    };

    class Symbol : public Node {
        DECLARE_RTTI(Symbol, Node);

      private:
        Ref<Type> SymbolType;
        std::string SymbolName;

      public:
        Symbol(Ref<Type> type, const std::string& name)
            : SymbolType(type)
            , SymbolName(name) {
        }

        const Ref<Type> type() const {
            return SymbolType;
        }

        const std::string& name() const {
            return SymbolName;
        }
    };

    class VariableDef : public Symbol {
        DECLARE_RTTI(VariableDef, Symbol);

      public:
        VariableDef(Ref<Type> type, const std::string& name)
            : Symbol(type, name) {
        }
    };

    class Expression : public Node {
        DECLARE_RTTI(Expression, Node);
    };

    class VariableRef : public Expression {
        DECLARE_RTTI(VariableRef, Expression);

      private:
        const std::string Identifier;

      public:
        VariableRef(const std::string& identifier);

        const std::string& identfier() const {
            return Identifier;
        }
    };

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

        Ref<Type> returnType() const {
            return ReturnType;
        }

        const std::vector<Symbol>& params() const {
            return Params;
        }

        bool isVararg() const {
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
            : FunctionNode(returnType, name, params, varargs) {
        }
    };

    class ExternFunction : public FunctionNode {
        DECLARE_RTTI(ExternFunction, FunctionNode);

      public:
        ExternFunction(Ref<Type> returnType,
                       const std::string& name,
                       const std::vector<Symbol>& params,
                       bool varargs = false)
            : FunctionNode(returnType, name, params, varargs) {
        }
    };

    class FunctionCall : public Expression {
        DECLARE_RTTI(FunctionCall, Expression);
        Ref<FunctionDef> Target;
        const std::vector<Ref<Expression>>& Args;

      public:
        FunctionCall(Ref<FunctionDef> target, const std::vector<Ref<Expression>>& args);
    };

}; // namespace pepper::ast
