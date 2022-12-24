
#pragma once

#include "Core/Common.h"
#include <memory>
#include <string>

namespace pepper {
    class Codegen;

    namespace ast {
        class AST;
    }

    struct SourceLocation {
        const std::string File;
        const int Line;

        SourceLocation(const std::string& file, int line)
            : File(file)
            , Line(line) {
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
