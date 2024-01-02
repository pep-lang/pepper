
#include "Core/Exceptions.h"

#include "Core/String.h"

namespace pepper {
    SourceLocation CompileError::Source;

    std::string CompileError::format(const SourceLocation& source, const std::string& msg) {
        const auto line = Sources::getLine(source);
        const auto marker = repeat("~", std::max<size_t>(0, source.Column - 1)) + "^";
        return llvm::formatv("{0}({1}):\n{2}\n{3}^\n{4}", source.File, source.Line, line, marker, msg);
    }
} // namespace pepper
