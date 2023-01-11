//
// Created by justi on 1/11/2023.
//

#pragma once

#include "API.h"

extern "C" {
    SUPPORT_API void SupportInit();

    SUPPORT_API void debug_ptr(const void* ptr, const char* name);
}
