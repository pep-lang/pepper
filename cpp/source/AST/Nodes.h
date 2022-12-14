#pragma once

#include "Core/Common.h"
#include "Core/RTTI.h"
#include <string>
#include <vector>

class Type;
class Value;
class Function;
class TypedValue;

namespace ast {

    class Node {
        DECLARE_RTTI(Node);

      public:
        Node() = default;
        virtual ~Node() = default;
    };

    class VariableDecl : public Node {
        DECLARE_RTTI(VariableDecl, Node);

      private:
        Ref<Type> VarType;
        std::string VarName;

      public:
        VariableDecl(const std::string& type, const std::string& name);
    };

    class Expression : public Node {
        DECLARE_RTTI(Expression, Node);
    };

    class VariableRef : public Expression {
        DECLARE_RTTI(VariableRef, Expression);

      private:
        Ref<Value> Variable;

      public:
        VariableRef(const std::string& identifier);
    };

    class FunctionNode : public Node {
        DECLARE_RTTI(FunctionNode, Node);

      private:
        Ref<Function> Func;

      public:
        FunctionNode(const std::string& returnType, const std::vector<TypedValue>& params, bool varargs = false);
    };

    class FunctionDef : public FunctionNode {
        DECLARE_RTTI(FunctionDef, FunctionNode);

      private:
        std::vector<Ref<Node>> Body;

      public:
        using FunctionNode::FunctionNode;
    };

    class ExternFunction : public FunctionNode {
        DECLARE_RTTI(ExternFunction, FunctionNode);

      public:
        using FunctionNode::FunctionNode;
    };

    class FunctionCall : public Node {
        DECLARE_RTTI(FunctionCall, Node);

      public:
        FunctionCall(const std::string& name, const std::vector<Ref<Expression>>& args);
    };

}; // namespace ast
