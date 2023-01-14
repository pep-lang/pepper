//
// Created by Justin Boswell on 12/29/22.
//
//
// Created by Justin Boswell on 12/26/22.
//
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(Loops, While) {
    const char* source = R"SOURCE(
        int test() {
            int x = 10;
            while (x > 0)
                x -= 1;
            return x;
        }
        )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}
