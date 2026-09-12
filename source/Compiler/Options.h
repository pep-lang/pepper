#pragma once

#include <iostream>
#include <string>

#include "Core/Common.h"
#include "Core/Vector.h"

namespace pepper {
    struct Options {
        std::string program_path;
        std::string primary_source_file;
        Vector<std::string> source_files;
        Vector<std::string> import_paths;
        Vector<std::string> forced_imports;
        Vector<std::string> libraries;
        std::string output_path;
        std::string exe_name;
        std::string build_dir;
        std::unique_ptr<std::istream> input_stream; // used internally for tests/embedding
        bool emit_llvm = false;
        bool verbose = false;
        bool compile_runtime = true;
        bool emit_debug_info = false;
        uint64_t trace_channels = 0;
        bool msvc = false;

        static Ref<Options> from_command_line(int argc, const char** argv);
        static Ref<Options> defaults();
    };

} // namespace pepper
