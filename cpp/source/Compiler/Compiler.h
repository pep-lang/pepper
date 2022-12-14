
#pragma once

#include "Core/Common.h"
#include <memory>
#include <string>

class Context;
class Parser;
class Options;

class Compiler {
    std::unique_ptr<Context> Ctx;
    std::unique_ptr<Parser> ParserRef;

  public:
    Compiler(const std::string& moduleName);

    bool compile(const std::string& sourceFile);
    bool parse(std::istream& inputStream);

    static Ref<Compiler> Compile(Ref<Options> opts);
    static Ref<Compiler> Compile(const std::string& moduleName, std::istream& inputStream);
};
