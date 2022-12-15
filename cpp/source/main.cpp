#include "Compiler/Compiler.h"
#include <filesystem>
#include <fstream>

int main(int argc, char** argv) {
    if (argc > 1) {
        const char* sourceFile = argv[1];
        std::ifstream sourceStream(sourceFile, std::ios_base::in);
        auto sourcePath = std::filesystem::path(sourceFile);
        pepper::Compiler::Compile(sourcePath.filename().string(), sourceStream);
    }

    return 0;
}
