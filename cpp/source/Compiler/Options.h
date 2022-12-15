#pragma once

#include "Core/Common.h"
#include <string>
#include <vector>

namespace pepper {
    class Options {
        std::vector<std::string> SourceFiles;
        std::string OutputPath;
        std::string ModuleName;

      public:
        static Ref<Options> fromCommandLine(int argc, const char** argv);

      public:
        const std::vector<std::string>& sourceFiles() const {
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
