#pragma once

#include <iostream>
#include <string>

#include "Core/Common.h"
#include "Core/Vector.h"

namespace pepper {
    struct Options {
        Vector<std::string> SourceFiles;
        std::string OutputPath;
        std::string ExeName;
        std::string BuildDir;
        std::unique_ptr<std::istream> InputStream; // used internally for tests/embedding
        bool EmitLLVM = false;

        static Ref<Options> FromCommandLine(int argc, const char** argv);
        static Ref<Options> Defaults();
    };

} // namespace pepper
