
#pragma once

#include "Core/Common.h"
#include "llvm/ADT/StringMap.h"
#include <memory>
#include <string>
#include <vector>

namespace pepper {
    class Type;
} // namespace pepper::ast

namespace pepper::ast {
    class Node;
    class Builder;
    class AST {

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
