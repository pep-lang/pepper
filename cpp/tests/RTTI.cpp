
#include "gtest/gtest.h"

#include "Core/Common.h"

struct A {
    DECLARE_RTTI(A);
};

struct B {
    DECLARE_RTTI(B, A);
};

TEST(RTTI, Is){
    A a;
    B b;
    EXPECT_TRUE(a.is<A>());
    EXPECT_TRUE(b.is<A>());
};