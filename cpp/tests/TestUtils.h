#pragma once

#include <sstream>
#include <string>

#include "Codegen/ModuleContext.h"
#include "Compiler/Compiler.h"
#include "Core/Common.h"
#include "JIT/Executor.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/FormatVariadic.h"

#include "gtest/gtest.h"

namespace TestUtils {
    using namespace pepper;

    inline std::string TestName(::testing::TestInfo* ti) {
        return llvm::formatv("{0}.{1}", ti->test_suite_name(), ti->test_case_name());
    }

    inline int CompileAndRun(const std::string& name, const std::string& source, const std::string& entry = "test") {
        auto compiler = Compiler::Create(name);
        auto sourceStream = std::istringstream(source);
        auto context = compiler->compile(sourceStream, name);
        auto executor = Executor::Create();
        return executor->execute(context, entry);
    }
} // namespace TestUtils
