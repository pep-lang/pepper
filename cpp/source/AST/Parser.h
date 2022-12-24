
#pragma once

#include <memory>
#include <string>

#include "Core/Common.h"

namespace pepper {
    class Codegen;

    namespace ast {
        class AST;
    }

    struct SourceLocation {
        const std::string File;
        const size_t Line;
        const size_t Column;

        SourceLocation(const std::string& file, size_t line, size_t column = 0)
            : File(file)
            , Line(line)
            , Column(column) {
        }

        std::string toString() const;
    };

    class Parser {
      public:
        Parser() = default;
        ~Parser() = default;

        Ref<ast::AST> parse(std::istream& stream, const std::string& name = "");
    };

} // namespace pepper
