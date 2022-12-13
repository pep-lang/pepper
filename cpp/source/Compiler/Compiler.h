
#pragma once

#include <memory>
#include <string>

class Context;

class Compiler {
    std::unique_ptr<Context> Ctx;

  public:
    Compiler(const std::string& moduleName);
};
