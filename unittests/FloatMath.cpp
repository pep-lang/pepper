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

TEST(FloatMath, Auto) {
    const char* source = R"SOURCE(
        int test() {
            const x = 1.42;
            return x > 1;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
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

TEST(FloatMath, Sub) {
    const char* source = R"SOURCE(
        int test() {
            float x = 0.42;
            float y = 0.1;
            return (x - y) > 0;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(FloatMath, Mul) {
    const char* source = R"SOURCE(
        int test() {
            float x = 0.42;
            float y = 0.1;
            float z = x * y;
            return z < 0.043 && z > 0.041;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(FloatMath, Div) {
    const char* source = R"SOURCE(
        int test() {
            float x = 0.42;
            float y = 0.1;
            float z = x / y;
            return z < 4.2001 && z > 4.1999;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(FloatMath, Mod) {
    const char* source = R"SOURCE(
        int test() {
            float x = 0.42;
            float y = 0.05;
            float z = x % y;
            return z < 0.021 && z > 0.019;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(FloatMath, Pow) {
    const char* source = R"SOURCE(
        int test() {
            float x = 3;
            float y = 4.2;
            float z = x ** y;
            return z < 100.91 && z > 100.9;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(FloatMath, Negate) {
    const char* source = R"SOURCE(
        int test() {
            float x = 0.42;
            float y = -x;
            return y < 0.41;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}
