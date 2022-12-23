//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include "Core/Common.h"

namespace llvm {
    class Type;
}

namespace pepper::ast {
    class Node;
    class FunctionDef;
    class VariableDef;
    class Expression;
    class Symbol;

    class Builder {
      public:
        template <typename N, typename... Args>
        Ref<N> create(Args&&... args) {
            return Ref<N>::New(std::forward<decltype(args)>(args)...);
        }

        [[nodiscard]] virtual llvm::Type* findType(const std::string& name) const = 0;
        [[nodiscard]] virtual Ref<ast::FunctionDef> findFunction(const std::string& name) const = 0;
        [[nodiscard]] virtual Ref<ast::VariableDef> findVariable(const std::string& name) const = 0;
        [[nodiscard]] virtual Ref<ast::Symbol> findSymbol(const std::string& name) const = 0;

        virtual Builder* beginFunction(Ref<ast::FunctionDef> func) = 0;
        virtual Builder* endFunction() = 0;
        virtual Ref<FunctionDef> returnTarget() const = 0;
        virtual Builder* beginScope(const std::string& name = "Anonymous") = 0;
        virtual Builder* endScope() = 0;
        virtual void pushStack(Ref<ast::Node> value) = 0;
        virtual Ref<ast::Node> popStack() = 0;
        virtual Ref<ast::Node> peekStack(unsigned int idx) = 0;
        virtual Builder* type(llvm::Type* newType) = 0;
        virtual Builder* variable(Ref<ast::VariableDef> var) = 0;
        virtual Builder* expression(Ref<ast::Expression> expr) = 0;
    };
} // namespace pepper::ast
