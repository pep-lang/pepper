
#pragma once

#include <memory>
#include <string>

#include "AST/AST.h"
#include "Core/Common.h"

namespace pepper {
    class Parser {
      public:
        Parser() = default;
        ~Parser() = default;

        Ref<ast::AST> parse(std::istream& stream, const std::string& name = "");
    };
} // namespace pepper
