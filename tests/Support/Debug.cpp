#include <cstdio>

#include "Support.h"

extern "C" {
    void debug_ptr(const void* ptr, const char* name) {
        void* ptr2 = *(void**)ptr;
        printf("%s: %p -> %p\n", name, ptr, ptr2);
    }

    void SupportInit() {
    }
}
