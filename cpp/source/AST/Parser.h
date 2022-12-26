
#pragma once

#include <memory>
#include <string>

#include "Core/Common.h"

namespace pepper {
    class Codegen;

    namespace ast {
        class AST;
    }

    class Parser {
      public:
        Parser() = default;
        ~Parser() = default;

        Ref<ast::AST> parse(std::istream& stream, const std::string& name = "");
    };

} // namespace pepper
