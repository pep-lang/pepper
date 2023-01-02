#include <filesystem>
#include <fstream>
#include <sstream>

#include "Compiler/Compiler.h"

int main(int argc, char** argv) {
    if (argc > 1) {
        const char* sourceFile = argv[1];
        std::ifstream fileStream(sourceFile, std::ios_base::in);
        assert(fileStream.good());
        std::stringstream buffer;
        buffer << fileStream.rdbuf();
        auto contents = buffer.str();
        std::istringstream sourceStream(contents);
        auto sourcePath = std::filesystem::path(sourceFile);
        auto compiler = pepper::Compiler::Create(sourcePath.filename().string(), sourcePath.string());
        compiler->compile(sourceStream);
    }

    return 0;
}
