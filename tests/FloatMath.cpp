//
// Created by Justin Boswell on 12/23/22.
//
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(FloatMath, Let) {
    const char* source = R"SOURCE(
        int test() {
            float x = 0.42;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

TEST(FloatMath, Add) {
    const char* source = R"SOURCE(
        int test() {
            float x = 0.42;
            return (x + x) > 1;
        }
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}