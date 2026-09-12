//
// Created by Justin Boswell on 12/23/22.
//
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(FloatMath, Let) {
    const char* source = R"SOURCE(
        test(): int {
            var x = 0.42;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(FloatMath, Auto) {
    const char* source = R"SOURCE(
        test(): int {
            var x = 1.42;
            return x > 1;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(FloatMath, Add) {
    const char* source = R"SOURCE(
        test(): int {
            var x = 0.42;
            return (x + x) > 1;
        }
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(FloatMath, Sub) {
    const char* source = R"SOURCE(
        test(): int {
            var x = 0.42;
            var y = 0.1;
            return (x - y) > 0;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(FloatMath, Mul) {
    const char* source = R"SOURCE(
        test(): int {
            var x = 0.42;
            var y = 0.1;
            var z = x * y;
            return z < 0.043 && z > 0.041;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(FloatMath, Div) {
    const char* source = R"SOURCE(
        test(): int {
            var x = 0.42;
            var y = 0.1;
            var z = x / y;
            return z < 4.2001 && z > 4.1999;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(FloatMath, Mod) {
    const char* source = R"SOURCE(
        test(): int {
            var x = 0.42;
            var y = 0.05;
            var z = x % y;
            return z < 0.021 && z > 0.019;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(FloatMath, Pow) {
    const char* source = R"SOURCE(
        test(): int {
            var x = 3;
            var y = 4.2;
            var z = x ** y;
            return z < 100.91 && z > 100.9;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(FloatMath, Negate) {
    const char* source = R"SOURCE(
        test(): int {
            var x = 0.42;
            var y = -x;
            return y < 0.41;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}
