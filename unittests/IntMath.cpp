
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(IntMath, const) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 1;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, Auto) {
    const char* source = R"SOURCE(
        test(): int {
            const x = 1;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, BoolToInt) {
    const char* source = R"SOURCE(
        test(): int {
            return true;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, Add) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 1;
            const y: int = 4;
            return x + y;
        }
    )SOURCE";
    EXPECT_EQ(5, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, Sub) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 1;
            const y: int = -1;
            return y - x;
        }
    )SOURCE";
    EXPECT_EQ(-2, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, Mul) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 12;
            const y: int = 4;
            return y * x;
        }
    )SOURCE";
    EXPECT_EQ(48, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, Div) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 12;
            const y: int = 4;
            return x / y;
        }
    )SOURCE";
    EXPECT_EQ(3, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, Mod) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 12;
            const y: int = 5;
            return x % y;
        }
    )SOURCE";
    EXPECT_EQ(2, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, And) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 12;
            const y: int = 5;
            return x & y;
        }
    )SOURCE";
    EXPECT_EQ(4, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, Or) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 12;
            const y: int = 5;
            return x | y;
        }
    )SOURCE";
    EXPECT_EQ(13, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, Xor) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 19;
            const y: int = 7;
            return x ^ y;
        }
    )SOURCE";
    EXPECT_EQ(20, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, LShift) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 12;
            const y: int = 5;
            return x << y;
        }
    )SOURCE";
    EXPECT_EQ(384, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, RShift) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 72;
            const y: int = 5;
            return x >> y;
        }
    )SOURCE";
    EXPECT_EQ(2, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, Pow) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 4;
            const y: int = 3;
            return x ** y;
        }
    )SOURCE";
    EXPECT_EQ(64, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, AddAssign) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 12;
            x += 42;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(54, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, SubAssign) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 42;
            x -= 10;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(32, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, MulAssign) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 12;
            x *= 4;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(48, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, DivAssign) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 12;
            x /= 4;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(3, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, ModAssign) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 12;
            x %= 4;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, AndAssign) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 12;
            x &= 4;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(4, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, OrAssign) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 12;
            x |= 3;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(15, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, XorAssign) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 12;
            x ^= 3;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(15, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, LShiftAssign) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 12;
            x <<= 3;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(96, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, RShiftAssign) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 32;
            x >>= 3;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(4, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, LogicalAnd) {
    const char* source = R"SOURCE(
        test(): int {
            const x: bool = 12;
            const y: bool = 0;
            return x && y;
        }
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, LogicalOr) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 64;
            const y: int = 0;
            return x || y;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, PreIncrement) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 64;
            const y: int = ++x;
            return y == x;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, PreDecrement) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 64;
            const y: int = --x;
            return y == x;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, PostIncrement) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 64;
            const y: int = x++;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(65, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, PostDecrement) {
    const char* source = R"SOURCE(
        test(): int {
            var x: int = 64;
            const y: int = x--;
            return y - x;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, BitwiseNot) {
    const char* source = R"SOURCE(
        test(): int {
            return ~1;
        }
    )SOURCE";
    EXPECT_EQ(-2, CompileAndRun(TestName(test_info_), source, "test", false));
}

TEST(IntMath, LogicalNot) {
    const char* source = R"SOURCE(
        test(): int {
            const x: int = 64;
            return !x;
        }
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source, "test", false));
}
