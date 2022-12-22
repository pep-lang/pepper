#pragma once

#include "Core/Common.h"
#include "Core/RTTI.h"
#include <string>
#include <utility>
#include <vector>

namespace pepper {
    class Type;
    class Value;
    class Function;
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
        Symbol(Ref<Type> type, std::string name)
            : SymbolType(std::move(type))
            , SymbolName(std::move(name)) {
        }

        [[nodiscard]] Ref<Type> type() const {
            return SymbolType;
        }

        [[nodiscard]] const std::string& name() const {
            return SymbolName;
        }
    };

    class VariableDef : public Symbol {
        DECLARE_RTTI(VariableDef, Symbol);

      public:
        VariableDef(Ref<Type> type, const std::string& name)
            : Symbol(std::move(type), name) {
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
        explicit VariableRef(const std::string& identifier);

        [[nodiscard]] const std::string& identfier() const {
            return Identifier;
        }
    };

}; // namespace pepper::ast

#include "AST/Functions.inl"
#include "AST/Struct.inl"
