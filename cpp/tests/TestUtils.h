#pragma once

#include "Compiler/Compiler.h"
#include "Compiler/Context.h"
#include "Compiler/Executor.h"
#include "Core/Common.h"
#include <sstream>
#include <string>

namespace TestUtils {
    inline int CompileAndRun(const std::string& name, const std::string& source) {
        auto compiler = pepper::Compiler::Create(name);
        auto sourceStream = std::istringstream(source);
        if (!compiler->compile(sourceStream, name))
            return -1;
        auto& context = compiler->context();
        auto executor = context.executor();
        auto ctx = context.takeContext();
        auto module = context.takeModule();
        return executor->execute(std::move(ctx), std::move(module), "main");
        return 0;
    }
} // namespace TestUtils
