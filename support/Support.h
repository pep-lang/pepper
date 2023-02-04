
#pragma once

#include <cstdint>
#include <cstdlib>

#if !defined(SUPPORT_API)
#    define SUPPORT_API
#endif

extern "C" {
    SUPPORT_API void SupportInit(void (*assertFn)(bool, const char*));

    SUPPORT_API void trace_region(const void* ptr, size_t size, const char* name);
    SUPPORT_API void trace_ptr(const void* ptr, const char* name);
    SUPPORT_API void trace_int(int64_t value, const char* name);

    SUPPORT_API void test_assert(bool condition, const char* message);

    SUPPORT_API void* _pep_malloc(size_t size);
    SUPPORT_API void* _pep_realloc(void* ptr, size_t prevSize, size_t newSize);
    SUPPORT_API void _pep_free(void* ptr);
    SUPPORT_API void panic(const char* msg);
}
