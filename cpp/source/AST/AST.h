
#pragma once

#include <memory>
#include <string>

#include "Core/Common.h"
#include "Core/Vector.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    class Node;
    class Builder;

    class AST {
      private:
        Vector<Ref<ast::Node>> Roots;
        WeakRef<Builder> ActiveBuilder;

      public:
        AST();

        Ref<Builder> builder();

        void newRoot(Ref<ast::Node> root);

        [[nodiscard]] const Vector<Ref<ast::Node>>& roots() const {
            return Roots;
        }

        void dump() const;
    };
} // namespace pepper::ast
