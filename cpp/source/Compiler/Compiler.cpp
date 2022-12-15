
#include "Compiler/Compiler.h"

#include "Compiler/Context.h"
#include "Compiler/Options.h"
#include "Compiler/Parser.h"
#include <filesystem>
#include <fstream>
#include <iostream>

namespace pepper {
    Compiler::Compiler(const std::string& moduleName) {
        Ctx = std::make_unique<Context>(moduleName);
        ParserRef = std::make_unique<Parser>();
    }

    bool Compiler::parse(std::istream& inputStream, const std::string& sourceFile) {
        try {
            ParserRef->parse(inputStream, sourceFile);
        } catch (const std::exception& e) {
            std::cerr << e.what() << '\n';
            return false;
        }

        return true;
    }

    bool Compiler::compile(const std::string& sourceFile) {
        std::ifstream sourceStream(sourceFile, std::ios_base::in);
        auto sourcePath = std::filesystem::path(sourceFile);
        return parse(sourceStream, sourceFile);
    }

    Ref<Compiler> Compiler::Compile(const std::string& moduleName, std::istream& inputStream) {
        auto compiler = std::make_shared<Compiler>(moduleName);
        if (compiler->parse(inputStream)) {
            return compiler;
        }
        return nullptr;
    }

    Ref<Compiler> Compiler::Compile(Ref<Options> opts) {
        Ref<Compiler> compiler = std::make_shared<Compiler>(opts->moduleName());
        for (auto sourceFile : opts->sourceFiles()) {
            compiler->compile(sourceFile);
        }
        return compiler;
    }

} // namespace pepper
