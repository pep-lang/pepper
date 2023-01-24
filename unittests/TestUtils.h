#pragma once

#include <string>

#include "Core/Common.h"
#include "gtest/gtest.h"

namespace TestUtils {
    using namespace pepper;

    std::string TestName(::testing::TestInfo* ti);

    int CompileAndRun(
        const std::string& name, const std::string& source, const std::string& entry = "test", bool runtime = true);
} // namespace TestUtils
