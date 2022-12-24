
#include "TestUtils.h"
#include "gtest/gtest.h"

TEST(IntMath, Let) {
    const char* source = R"SOURCE(
        int test() {
            int x = 1;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(1, TestUtils::CompileAndRun(this->test_info_->name(), source));
}

TEST(IntMath, Add) {
    const char* source = R"SOURCE(
        int test() {
            int x = 1;
            int y = 4;
            return x + y;
        }
    )SOURCE";
    EXPECT_EQ(5, TestUtils::CompileAndRun(this->test_info_->name(), source));
}
