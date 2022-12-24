#pragma once

#include <sstream>
#include <string>

#include "Codegen/ModuleContext.h"
#include "Compiler/Compiler.h"
#include "Core/Common.h"
#include "JIT/Executor.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"

namespace TestUtils {
    using namespace pepper;

    inline int CompileAndRun(const std::string& name, const std::string& source, const std::string& entry = "test") {
        auto compiler = Compiler::Create(name);
        auto sourceStream = std::istringstream(source);
        auto context = compiler->compile(sourceStream, name);
        auto executor = Executor::Create();
        return executor->execute(context, entry);
    }
} // namespace TestUtils
