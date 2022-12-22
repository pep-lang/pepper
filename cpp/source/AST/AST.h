
#pragma once

#include "Core/Common.h"
#include "llvm/ADT/StringMap.h"
#include <memory>
#include <string>
#include <vector>

namespace pepper {
    class Type;
} // namespace pepper

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

        [[nodiscard]] const std::vector<Ref<ast::Node>>& roots() const {
            return Roots;
        }
    };
} // namespace pepper::ast
