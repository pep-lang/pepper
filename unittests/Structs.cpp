//
// Created by Justin Boswell on 12/23/22.
//
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(Structs, Simple) {
    const char* source = R"SOURCE(
struct Test {
    var x = 0;
};

test(): int {
    var t = Test();
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, SizeOf) {
    const char* source = R"SOURCE(
struct Test {
    var x = 0;
};

test(): int {
    return sizeof<Test>();
}
    )SOURCE";
    EXPECT_EQ(8, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, SizeOfGeneric) {
    const char* source = R"SOURCE(
struct Test<T> {
    var x = 0;
};

extend Test<T> {
    size(): int {
        return sizeof<T>();
    }
}

test(): int {
    let t = Test<int>();
    return t.size();
}
    )SOURCE";
    EXPECT_EQ(4, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, Constructor) {
    const char* source = R"SOURCE(
struct Test {
    var x = 0;

    new(this.x = 1) {}
};

test(): int {
    var t = Test();
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, Extension) {
    const char* source = R"SOURCE(
struct Test {
    var x: int;
    new() {
        x = 1;
    }
};

extend Test {
    setX(newX: int): void {
        x = newX;
    }
}

test(): int {
    var t = Test();
    t.setX(10);
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(10, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, Range) {
    const char* source = R"SOURCE(
struct range_test {
    var start: int;
    var current = 0xffffffff;
    var end: int;
    var step: int;

    new(this.start, this.end = -1, this.step=1) {
        if (end == -1) {
            end = start + 1;
            step = 0;
        }
    }
}

extend range_test {
    next(): bool {
        if (current == 0xffffffff) {
            current = start;
        } else {
            current += step;
        }
        return current < end;
    }

    value(): int {
        return current;
    }
}

test(): int {
    var r = range_test(0, 10);
    var x = 0;
    while (r.next()) {
        x += 1;
    }
    return x;
}
    )SOURCE";
    EXPECT_EQ(10, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, SimpleGeneric) {
    const char* source = R"SOURCE(
struct Test<T> {
    var x: T;
};

test(): int {
    let t = Test<int>();
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, SimpleGenericCtor) {
    const char* source = R"SOURCE(
struct Test<T> {
    var x: T;

    new(this.x) {}
};

test(): int {
    let t = Test<int>(2);
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(2, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, RangeGeneric) {
    const char* source = R"SOURCE(
struct range_test<T> {
    var start;
    var current;
    var end;
    var step;

    new(this.start, this.end = -1, this.step=1) {
        if (end == -1) {
            end = start + 1;
            step = 0;
        }
        current = start - step;
    }
}

extend range_test<T> {
    next(): bool {
        if ((current + step) == start) {
            current = start;
        } else {
            current += step;
        }
        return current < end;
    }

    value(): T {
        return current;
    }
}

test(): int {
    var r = range_test<int>(0, 10);
    var x = 0;
    while (r.next()) {
        x += 1;
    }
    return x;
}
    )SOURCE";
    EXPECT_EQ(10, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, RefArgument) {
    const char* source = R"SOURCE(
struct Test {
    var x = 2;
};

getX(t: Test): int {
    return t.x;
}

test(): int {
    var t = Test();
    var x = getX(t);
    return x;
}
    )SOURCE";
    EXPECT_EQ(2, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, AcquireRelease) {
    const char* source = R"SOURCE(
struct Test {
    var x = 2;
};

test(): int {
    var t = Test();
    trace_int(t.__refcount, @"t.__refcount");
    test_assert(t.__refcount == 1, @"t.__refcount == 1");
    var prev = t;
    test_assert(t === prev, @"t === prev");
    test_assert(prev.__refcount == 2, @"prev.__refcount == 2");
    t = Test();
    test_assert(prev.__refcount == 1, @"prev.__refcount == 1");
    test_assert(t.__refcount == 1, @"t.__refcount == 1");
    return 0;
}
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}
