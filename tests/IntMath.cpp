
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

TEST(IntMath, BoolToInt) {
    const char* source = R"SOURCE(
        int test() {
            return true;
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

TEST(IntMath, Div) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            int y = 4;
            return x / y;
        }
    )SOURCE";
    EXPECT_EQ(3, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, Mod) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            int y = 5;
            return x % y;
        }
    )SOURCE";
    EXPECT_EQ(2, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, And) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            int y = 5;
            return x & y;
        }
    )SOURCE";
    EXPECT_EQ(4, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, Or) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            int y = 5;
            return x | y;
        }
    )SOURCE";
    EXPECT_EQ(13, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, Xor) {
    const char* source = R"SOURCE(
        int test() {
            int x = 19;
            int y = 7;
            return x ^ y;
        }
    )SOURCE";
    EXPECT_EQ(20, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, LShift) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            int y = 5;
            return x << y;
        }
    )SOURCE";
    EXPECT_EQ(384, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, RShift) {
    const char* source = R"SOURCE(
        int test() {
            int x = 72;
            int y = 5;
            return x >> y;
        }
    )SOURCE";
    EXPECT_EQ(2, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, AddAssign) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            x += 42;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(54, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, SubAssign) {
    const char* source = R"SOURCE(
        int test() {
            int x = 42;
            x -= 10;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(32, CompileAndRun(TestName(test_info_), source));
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

TEST(IntMath, DivAssign) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            x /= 4;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(3, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, ModAssign) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            x %= 4;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, AndAssign) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            x &= 4;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(4, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, OrAssign) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            x |= 3;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(15, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, XorAssign) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            x ^= 3;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(15, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, LShiftAssign) {
    const char* source = R"SOURCE(
        int test() {
            int x = 12;
            x <<= 3;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(96, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, RShiftAssign) {
    const char* source = R"SOURCE(
        int test() {
            int x = 32;
            x >>= 3;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(4, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, LogicalAnd) {
    const char* source = R"SOURCE(
        int test() {
            bool x = 12;
            bool y = 0;
            return x && y;
        }
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

TEST(IntMath, LogicalOr) {
    const char* source = R"SOURCE(
        int test() {
            int x = 64;
            int y = 0;
            return x || y;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}
