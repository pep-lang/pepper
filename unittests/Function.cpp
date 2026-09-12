//
// Created by Justin Boswell on 12/26/22.
//
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(Function, Sum) {
    const char* source = R"SOURCE(
        sum(x: int, y: int): int {
            return x + y;
        }

        test(): int {
            return sum(64, 1);
        }
        )SOURCE";
    EXPECT_EQ(65, CompileAndRun(TestName(test_info_), source));
}

TEST(Function, NestedCalls) {
    const char* source = R"SOURCE(
        mul(a: int, b: int): int {
            return a * b;
        }
        sum(x: int, y: int): int {
            return x + y;
        }

        test(): int {
            return sum(mul(8,8), mul(1, 1));
        }
        )SOURCE";
    EXPECT_EQ(65, CompileAndRun(TestName(test_info_), source));
}

TEST(Function, DefaultParams) {
    const char* source = R"SOURCE(
        addTo(x: int, y: int = 1): int {
            return x + y;
        }

        test(): int {
            return addTo(64);
        }
        )SOURCE";
    EXPECT_EQ(65, CompileAndRun(TestName(test_info_), source));
}

TEST(Function, Extern) {
    const char* source = R"SOURCE(
        extern int strlen(char* str);

        test(): int {
            return strlen(@"test");
        }
        )SOURCE";
    EXPECT_EQ(4, CompileAndRun(TestName(test_info_), source));
}

TEST(Function, Generic) {
    const char* source = R"SOURCE(
        sum<T>(x: T, y: T): T {
            return x + y;
        }

        test(): int {
            return sum<int>(64, 1);
        }
        )SOURCE";
    EXPECT_EQ(65, CompileAndRun(TestName(test_info_), source));
}
