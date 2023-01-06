
#pragma once

#include <memory>
#include <string>

#include "AST/Node.h"
#include "Core/Common.h"
#include "Core/Vector.h"
#include "llvm/ADT/StringMap.h"

namespace pepper::ast {
    class Builder;

    class AST {
      private:
        Vector<Ref<ast::Node>> Roots;
        std::unique_ptr<Builder> TreeBuilder;

      public:
        AST();

        Builder* builder();

        void newRoot(Ref<ast::Node> root);

        [[nodiscard]] const Vector<Ref<ast::Node>>& roots() const {
            return Roots;
        }

        void dump() const;
    };
} // namespace pepper::ast

#define PEP_TRACE_AST(fmt, ...) PEP_TRACE(TraceChannel::AST, fmt, __VA_ARGS__)
