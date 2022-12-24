
#include "Core/Common.h"
#include "gtest/gtest.h"

struct A {
    DECLARE_RTTI(A);
};

struct B : A {
    DECLARE_RTTI(B, A);
};

TEST(RTTI, Is) {
    A a;
    B b;
    EXPECT_TRUE(a.is<A>());
    EXPECT_TRUE(b.is<A>());
};