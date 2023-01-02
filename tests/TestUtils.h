#pragma once

#include <sstream>
#include <string>

#include "Codegen/ModuleContext.h"
#include "Compiler/Compiler.h"
#include "Core/Common.h"
#include "JIT/Executor.h"
#include "gtest/gtest.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/FormatVariadic.h"

namespace TestUtils {
    using namespace pepper;

    inline std::string TestName(::testing::TestInfo* ti) {
        return llvm::formatv("{0}.{1}", ti->test_suite_name(), ti->name());
    }

    inline int CompileAndRun(const std::string& name, const std::string& source, const std::string& entry = "test") {
        auto compiler = Compiler::Create(name, name);
        auto sourceStream = std::istringstream(source);
        auto context = compiler->compile(sourceStream);
        auto executor = Executor::Create();
        return executor->execute(context, entry);
    }
} // namespace TestUtils
