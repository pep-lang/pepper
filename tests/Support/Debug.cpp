//
// Created by justi on 1/11/2023.
//
#include <cstdio>

#include "Support.h"

extern "C" {
    void debug_ptr(const void* ptr, const char* name) {
        void* ptr2 = *(void**)ptr;
        void* ptr3 = *(void**)ptr2;
        printf("%s: %p -> %p -> %p\n", name, ptr, ptr2, ptr3);
    }

    void SupportInit() {
    }
}
