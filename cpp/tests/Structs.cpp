//
// Created by Justin Boswell on 12/23/22.
//
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(Structs, Simple) {
    const char* source = R"SOURCE(
        struct Test {
            int x = 0;
        };

        int test() {
            Test t = Test();
            return t.x;
        }
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}