#include "Compiler/Compiler.h"
#include <filesystem>
#include <fstream>

int main(int argc, char** argv) {
    if (argc > 1) {
        const char* sourceFile = argv[1];
        std::ifstream sourceStream(sourceFile, std::ios_base::in);
        auto sourcePath = std::filesystem::path(sourceFile);
        auto compiler = pepper::Compiler::Create(sourcePath.filename().string());
        return compiler->compile(sourceStream, sourcePath) != nullptr;
    }

    return 0;
}
