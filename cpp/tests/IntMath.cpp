
#include "gtest/gtest.h"

#include "TestUtils.h"

TEST(IntMath, Let) {
    const char* source = R"SOURCE(
        int main() {
            let x = 1;
            return x;
        }
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun("Let", source));
}
