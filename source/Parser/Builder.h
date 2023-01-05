//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include "AST.h"
#include "AST/Nodes.h"
#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/SourceLocation.h"

namespace pepper::ast {
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

        [[nodiscard]] virtual Ref<StructDef> findStruct(const Ident& name) const = 0;
        [[nodiscard]] virtual Ref<FunctionDef> findFunction(const Ident& name) const = 0;
        [[nodiscard]] virtual Ref<VariableDef> findVariable(const Ident& name) const = 0;
        [[nodiscard]] virtual Ref<Symbol> findSymbol(const Ident& name) const = 0;

        virtual void beginStruct(Ref<StructDef> st) = 0;
        virtual void endStruct() = 0;

        virtual void beginExtension(Ref<StructDef> structDef) = 0;
        virtual void endExtension() = 0;

        virtual Ref<StructDef> structTarget() const = 0;

        virtual void beginFunction(Ref<FunctionDef> func) = 0;
        virtual void endFunction() = 0;
        virtual Ref<FunctionDef> functionTarget() const = 0;

        virtual void beginBlock(Ref<Block> block) = 0;
        virtual void endBlock() = 0;
        virtual Ref<Block> block() const = 0;

        virtual void beginScope(const Ident& name = "Anonymous") = 0;
        virtual void endScope() = 0;

        virtual void pushRValue(Ref<Node> value) = 0;
        virtual Ref<Node> popRValue() = 0;
        virtual Ref<Node> peekRValue(unsigned int idx) const = 0;

        virtual void pushLValue(Ref<Node> value) = 0;
        virtual Ref<Node> popLValue() = 0;
        virtual Ref<Node> peekLValue(unsigned int idx) const = 0;

        virtual Ref<StructDef> specialize(const TypeName& structSpec) = 0;
        virtual void symbol(Ref<VariableDef> var) = 0;
        virtual void insert(Ref<Node> expr) = 0;

        virtual void trace(const Ref<Node>& node) const = 0;
    };
} // namespace pepper::ast
