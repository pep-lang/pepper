
#pragma once

#include <string>

#include "Core/Vector.h"
#include "llvm/Support/FormatVariadic.h"

namespace pepper {
    struct SourceLocation {
        std::string File;
        size_t Line;
        size_t Column;

        SourceLocation(const std::string& file = "", size_t line = 0, size_t column = 0)
            : File(file)
            , Line(line)
            , Column(column) {}

        std::string toString() const {
            return llvm::formatv("{0}({1},{2})", File, Line, Column);
        }

        bool operator==(const SourceLocation& other) const {
            return Line == other.Line && Column == other.Column && File == other.File;
        }

        bool operator!=(const SourceLocation& other) const {
            return !(*this == other);
        }
    };

    struct SourceFile {
        std::string Name;
        Vector<std::string> Lines;
    };

    struct Sources {
        static void add(const SourceFile& sourceFile);
        static const SourceFile& get(const std::string& name);
        static const std::string& getLine(const SourceLocation& source);
        static const std::string& getLine(const std::string& name, size_t line);
    };
} // namespace pepper