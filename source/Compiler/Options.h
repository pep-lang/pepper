#pragma once

#include <iostream>
#include <string>

#include "Core/Common.h"
#include "Core/Vector.h"

namespace pepper {
    struct Options {
        std::string ProgramPath;
        std::string PrimarySourceFile;
        Vector<std::string> SourceFiles;
        Vector<std::string> ImportPaths;
        Vector<std::string> ForcedImports;
        Vector<std::string> Libraries;
        std::string OutputPath;
        std::string ExeName;
        std::string BuildDir;
        std::unique_ptr<std::istream> InputStream; // used internally for tests/embedding
        bool EmitLLVM = false;
        bool Verbose = false;
        bool CompileRuntime = true;
        bool EmitDebugInfo = false;
        unsigned TraceChannels = 0;

        static Ref<Options> FromCommandLine(int argc, const char** argv);
        static Ref<Options> Defaults();
    };

} // namespace pepper
