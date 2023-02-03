
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

static void (*AssertFn)(bool, const char*);

extern "C" {
    void trace_region(const void* ptr, size_t size, const char* name) {
        const size_t* base = (size_t*)ptr;
        if (auto rem = (size % sizeof(size_t)))
            size += sizeof(size_t) - rem;
        auto width = printf("%s: %p -> %016zX\n", name, ptr, base ? *base : 0);
        if (base) {
            for (int idx = 1; idx < size / sizeof(size_t); ++idx) {
                auto addr = base + idx;
                printf("%*c%0*zX\n", width - 16 - 1, ' ', 16, *addr);
            }
        }
        fflush(stdout);
    }

    void trace_ptr(const void* ptr, const char* name) {
        trace_region(ptr, sizeof(size_t), name);
    }

    void trace_int(int64_t value, const char* name) {
        printf("%s: %lld\n", name, value);
        fflush(stdout);
    }

    void _pep_assert(bool condition, const char* message) {
        if (AssertFn) {
            AssertFn(condition, message);
            return;
        }
        fprintf(stderr, "%s\n", message);
        fflush(stderr);
        assert(condition);
    }

    void* _pep_malloc(size_t size) {
        void* ptr = malloc(size);
        memset(ptr, 0, size);
        return ptr;
    }

    void* _pep_realloc(void* ptr, size_t prevSize, size_t newSize) {
        ptr = realloc(ptr, newSize);
        if (newSize > prevSize)
            memset((uint8_t*)ptr + prevSize, 0, newSize - prevSize);
        return ptr;
    }

    void _pep_free(void* ptr) {
        free(ptr);
    }

    void SupportInit(void (*assertFn)(bool, const char*)) {
        AssertFn = assertFn;
    }
}
