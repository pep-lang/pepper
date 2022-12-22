
#include "TestUtils.h"
#include "gtest/gtest.h"

TEST(IntMath, Let) {
    const char* source = R"SOURCE(
        int main() {
            let x = 1;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(1, TestUtils::CompileAndRun("Let", source));
}
