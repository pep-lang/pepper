#pragma once

#include <string>

#include "Core/Common.h"
#include "Core/Vector.h"

namespace pepper {
    class Options {
        Vector<std::string> SourceFiles;
        std::string OutputPath;
        std::string ModuleName;

      public:
        static Ref<Options> fromCommandLine(int argc, const char** argv);

      public:
        const Vector<std::string>& sourceFiles() const {
            return SourceFiles;
        }

        const std::string& moduleName() const {
            return ModuleName;
        }

        const std::string& outputPath() const {
            return OutputPath;
        }
    };

} // namespace pepper
