//
// Created by justi on 5/14/2025.
//

#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(Parsing, Release) {
    const char* source = R"SOURCE(
        release<T>(t: T): void {
            trace_ptr(t, @"release<T>");
            t.__release();
        }
    )SOURCE";
    EXPECT_EQ(0, Compile(TestName(test_info_), source, "test", false));
}

TEST(Parsing, Ptr) {
    const char* source = R"SOURCE(
        assert(condition: bool, msg: __ptr<char>): void {
            
        }
    )SOURCE";
    EXPECT_EQ(0, Compile(TestName(test_info_), source, "test", false));
}

TEST(Parsing, Extern) {
    const char* source = R"SOURCE(
        extern void trace_region(void* ptr, ulong size, char* msg);
    )SOURCE";
    EXPECT_EQ(0, Compile(TestName(test_info_), source, "test", false));
}
