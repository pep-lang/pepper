
#include "Core/Exceptions.h"

#include "Core/String.h"

namespace pepper {
    SourceLocation CompileError::Source;

    std::string CompileError::format(const SourceLocation& source, const std::string& msg) {
        const auto line = Sources::get_line(source);
        if (!line.empty()) {
            const auto marker = repeat("~", std::max<ssize_t>(0, source.column - 1)) + "^";
            return llvm::formatv("{0}({1}):\n{2}\n{3}^\n{4}", source.file, source.line, line, marker, msg);
        }
        return msg;
    }
} // namespace pepper
