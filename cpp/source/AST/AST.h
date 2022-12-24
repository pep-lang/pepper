
#pragma once

#include <memory>
#include <string>
#include <vector>

#include "Core/Common.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    class Node;
    class Builder;

    class AST {
      private:
        std::vector<Ref<ast::Node>> Roots;
        WeakRef<Builder> ActiveBuilder;

      public:
        AST();

        Ref<Builder> builder();

        void newRoot(Ref<ast::Node> root);

        [[nodiscard]] const std::vector<Ref<ast::Node>>& roots() const {
            return Roots;
        }
    };
} // namespace pepper::ast
