//
// Created by Justin Boswell on 12/26/22.
//

//
// Created by Justin Boswell on 12/23/22.
//
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(Function, Sum) {
const char* source = R"SOURCE(
    int sum(int x, int y) {
        return x + y;
    }

    int test() {
        return sum(64, 1);
    }
    )SOURCE";
EXPECT_EQ(65, CompileAndRun(TestName(test_info_), source));
}
