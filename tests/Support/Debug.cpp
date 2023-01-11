#include <cassert>
#include <cstdio>

#include "Support.h"

static void (*AssertFn)(bool, const char*);

extern "C" {
    void debug_ptr(const void* ptr, const char* name) {
        void* ptr2 = *(void**)ptr;
        printf("%s: %p -> %p\n", name, ptr, ptr2);
    }

    void test_assert(bool condition, const char* message) {
        if (AssertFn) {
            AssertFn(condition, message);
            return;
        }
        assert(condition);
    }

    void SupportInit(void (*assertFn)(bool, const char*)) {
        AssertFn = assertFn;
    }
}
