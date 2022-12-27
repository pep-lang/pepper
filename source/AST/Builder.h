//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include "Core/Common.h"
#include "Core/Name.h"
#include "Core/SourceLocation.h"

namespace llvm {
    class Type;
}

namespace pepper::ast {
    class Node;
    class FunctionDef;
    class VariableDef;
    class StructDef;
    class Expression;
    class Symbol;

    class Builder {
      public:
        template <typename N, typename... Args>
        Ref<N> NewAt(const SourceLocation& source, Args&&... args) {
            auto node = Ref<N>::New(std::forward<decltype(args)>(args)...);
            node->Source = source;
            trace(node);
            return node;
        }

        template <typename N, typename... Args>
        Ref<N> New(Args&&... args) {
            return NewAt<N>(Source, std::forward<decltype(args)>(args)...);
        }

        SourceLocation Source;

        [[nodiscard]] virtual Ref<StructDef> findStruct(const Name& name) const = 0;
        [[nodiscard]] virtual Ref<FunctionDef> findFunction(const Name& name) const = 0;
        [[nodiscard]] virtual Ref<VariableDef> findVariable(const Name& name) const = 0;
        [[nodiscard]] virtual Ref<Symbol> findSymbol(const Name& name) const = 0;

        virtual Builder* beginStruct(Ref<StructDef> str) = 0;
        virtual Builder* endStruct() = 0;
        virtual Ref<StructDef> structTarget() const = 0;
        virtual Builder* beginFunction(Ref<FunctionDef> func) = 0;
        virtual Builder* endFunction() = 0;
        virtual Ref<FunctionDef> functionTarget() const = 0;

        virtual Builder* beginScope(const Name& name = "Anonymous") = 0;
        virtual Builder* endScope() = 0;

        virtual void pushRValue(Ref<Expression> value) = 0;
        virtual Ref<Expression> popRValue() = 0;
        virtual Ref<Expression> peekRValue(unsigned int idx) const = 0;

        virtual void pushLValue(Ref<Node> value) = 0;
        virtual Ref<Node> popLValue() = 0;
        virtual Ref<Node> peekLValue(unsigned int idx) const = 0;

        virtual Builder* symbol(Ref<VariableDef> var) = 0;
        virtual Builder* expression(Ref<Expression> expr) = 0;
        virtual void trace(const Ref<Node>& node) const = 0;
    };
} // namespace pepper::ast
