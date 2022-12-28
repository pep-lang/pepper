//
// Created by Justin Boswell on 12/26/22.
//
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(Branches, DISABLED_If) {
    const char* source = R"SOURCE(
        int test() {
            int x = 0;
            if (x == 0)
                x = 1;
            return x;
        }
        )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(Branches, DISABLED_IfElse) {
    const char* source = R"SOURCE(
        int test() {
            int x = 1;
            if (x) {
                x = 2;
            } else {
                x = 3;
            }
        }
        )SOURCE";
    EXPECT_EQ(2, CompileAndRun(TestName(test_info_), source));
}
