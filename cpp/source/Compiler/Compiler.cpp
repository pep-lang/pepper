
#include "Compiler/Compiler.h"

#include "Compiler/Context.h"

Compiler::Compiler(const std::string& moduleName) { Ctx = std::make_unique<Context>(moduleName); }
