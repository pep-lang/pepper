//
// Created by justi on 1/11/2023.
//

#pragma once

#include "API.h"

extern "C" {
    SUPPORT_API void SupportInit(void (*assertFn)(bool, const char*));

    SUPPORT_API void debug_ptr(const void* ptr, const char* name);

    SUPPORT_API void test_assert(bool condition, const char* message);
}
