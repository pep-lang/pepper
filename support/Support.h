
#pragma once

#include <cstdint>
#include <cstdlib>

extern "C" {
    void SupportInit(void (*assertFn)(bool, const char*));

    void trace_region(const void* ptr, size_t size, const char* name);
    void trace_ptr(const void* ptr, const char* name);
    void trace_int(int64_t value, const char* name);

    void _pep_assert(bool condition, const char* message);
}
