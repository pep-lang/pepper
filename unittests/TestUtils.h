#pragma once

#include <string>

#include "Core/Common.h"
#include "JIT/Executor.h"
#include "gtest/gtest.h"

namespace TestUtils {
    using namespace pepper;

    std::string TestName(::testing::TestInfo* ti);

    int CompileAndRun(
        const std::string& name, const std::string& source, const std::string& entry = "test", bool runtime = true);

    Vector<std::string> CompileModule(
        const std::string& name, const std::string& source, const std::string& entry, bool compileRuntime);

    int Compile(
        const std::string& name,
        const std::string& source,
        const std::string& entry = "test",
        bool runtime = true);

    template <typename T>
    T CompileAndRunResult(
        const std::string& name, const std::string& source, const std::string& entry, bool compileRuntime) {
        const auto obj_files = CompileModule(name, source, entry, compileRuntime);
        if (obj_files.empty()) {
            return -1;
        }
        const auto executor = Executor::create();
        return executor->invoke<T>(obj_files, entry);
    }
} // namespace TestUtils
