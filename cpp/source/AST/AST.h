
#pragma once

#include "Core/Common.h"
#include "llvm/ADT/StringMap.h"
#include <string>
#include <unordered_map>
#include <vector>

namespace ast {
    class Node;
    class FunctionDef;
    class VariableDecl;
    class Expression;
} // namespace ast

class AST {
  public:
    class Builder {
      public:
        virtual Builder* startFunction(Ref<ast::FunctionDef> func) = 0;
        virtual Builder* endFunction() = 0;
        virtual Builder* variable(Ref<ast::VariableDecl> var) = 0;
        virtual Builder* expression(Ref<ast::Expression> expr) = 0;
    };

  protected:
    std::vector<Ref<ast::Node>> Roots;
    llvm::StringMap<Ref<ast::Node>> Globals;
    llvm::StringMap<Ref<ast::Node>> Locals;

  public:
    AST();

    Ref<Builder> builder();
};
