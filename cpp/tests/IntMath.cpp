
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(IntMath, Let) {
    const char* source = R"SOURCE(
        int test() {
            int x = 1;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, Add) {
    const char* source = R"SOURCE(
        int test() {
            int x = 1;
            int y = 4;
            return x + y;
        }
    )SOURCE";
    EXPECT_EQ(5, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, Sub) {
    const char* source = R"SOURCE(
        int test() {
            int x = 1;
            int y = -1;
            return y - x;
        }
    )SOURCE";
    EXPECT_EQ(-2, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, Mul) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            int y = 4;
            return y * x;
        }
    )SOURCE";
    EXPECT_EQ(48, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, MulAssign) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            x *= 4;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(48, CompileAndRun(TestName(test_info_), source));
}
