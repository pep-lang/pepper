
#pragma once

#include "Core/Common.h"
#include "llvm/ADT/StringMap.h"
#include <memory>
#include <string>
#include <vector>

namespace pepper::ast {
    class Node;
    class FunctionDef;
    class VariableDef;
    class Expression;
    class Symbol;
} // namespace pepper::ast

namespace pepper {
    class Type;

    class AST {
      public:
        class Builder {
          public:
            template <typename N, typename... Args> Ref<N> create(Args&&... args) {
                return Ref<N>::create(std::forward<decltype(args)>(args)...);
            }

            virtual Ref<Type> findType(const std::string& name) const = 0;
            virtual Ref<ast::FunctionDef> findFunction(const std::string& name) const = 0;
            virtual Ref<ast::VariableDef> findVariable(const std::string& name) const = 0;
            virtual Ref<ast::Symbol> findSymbol(const std::string& name) const = 0;

            virtual Builder* beginFunction(Ref<ast::FunctionDef> func) = 0;
            virtual Builder* endFunction() = 0;
            virtual Builder* beginScope() = 0;
            virtual Builder* endScope() = 0;
            virtual void pushStack(Ref<ast::Node> value) = 0;
            virtual Ref<ast::Node> popStack() = 0;
            virtual Ref<ast::Node> peekStack(unsigned int idx) = 0;
            virtual Builder* type(Ref<Type> newType) = 0;
            virtual Builder* variable(Ref<ast::VariableDef> var) = 0;
            virtual Builder* expression(Ref<ast::Expression> expr) = 0;
        };

      private:
        std::vector<Ref<ast::Node>> Roots;
        llvm::StringMap<Ref<ast::Node>> Globals;
        llvm::StringMap<Ref<ast::Node>> Locals;
        WeakRef<Builder> ActiveBuilder;

      public:
        AST();

        Ref<Builder> builder();
    };
} // namespace pepper
