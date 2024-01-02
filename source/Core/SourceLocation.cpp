
#include "Core/SourceLocation.h"

#include "Core/Exceptions.h"
#include "llvm/ADT/StringMap.h"

namespace pepper {

    namespace {
        llvm::StringMap<SourceFile> Source;
    }

    void Sources::add(const SourceFile& sourceFile) {
        Source[sourceFile.Name] = sourceFile;
    }

    const SourceFile& Sources::get(const std::string& name) {
        if (auto it = Source.find(name); it != Source.end()) {
            return it->second;
        }
        throw InternalCompilerError("Unable to find source info for file {0}", name);
    }

    const std::string& Sources::getLine(const SourceLocation& source) {
        return getLine(source.File, source.Line);
    }

    const std::string& Sources::getLine(const std::string& name, size_t line) {
        const auto& [file, lines] = get(name);
        return lines[line];
    }

} // namespace pepper
