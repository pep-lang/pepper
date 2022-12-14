
#include "Compiler/Compiler.h"

#include "Compiler/Context.h"
#include "Compiler/Parser.h"
#include <iostream>

Compiler::Compiler(const std::string& moduleName) {
    Ctx = std::make_unique<Context>(moduleName);
    ParserRef = std::make_unique<Parser>(nullptr);
}

bool Compiler::parse(std::istream& inputStream) {
    try {
        ParserRef->parse(inputStream);
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return false;
    }

    return true;
}

Ref<Compiler> Compiler::Compile(const std::string& moduleName, std::istream& inputStream) {
    auto compiler = std::make_shared<Compiler>(moduleName);
    if (compiler->parse(inputStream)) {
        return compiler;
    }
    return nullptr;
}
