
#include <algorithm>
#include <cassert>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <shared_mutex>

#if _WIN32
#    define WIN32_LEAN_AND_MEAN
#    define NOGDI
#    ifndef NOMINMAX
#        define NOMINMAX
#    endif
#    include <windows.h>
#endif

struct Header {
    uint32_t size;
    uint32_t id;
};

static void (*AssertFn)(bool, const char*);

extern "C" {
    void SupportInit(void (*assertFn)(bool, const char*)) {
        AssertFn = assertFn;
    }

    void panic(const char* msg) {
        if (msg && msg[0]) {
            fprintf(stderr, "%s\n", msg);
            fflush(stderr);
        } else {
            fprintf(stderr, "Assertion failed with no additional information\n");
            fflush(stderr);
        }
        abort();
    }
}

#define MAX_GUARD_PAGES 1024

namespace {
    std::once_flag Initialized;
    std::once_flag Exited;
    std::shared_mutex MemLock;

    struct GuardPageRingBuffer {
        void* pages[MAX_GUARD_PAGES] = {};
        size_t tail = 0;
    } GuardPages;

    const char* GetEnv(const char* var) {
#if _WIN32
        char* value = nullptr;
        size_t len = 0;
        errno_t err = _dupenv_s(&value, &len, var);
        if (err || len == 0) {
            return nullptr;
        }
        return value;
#else
        return std::getenv(var);
#endif
    }

#if _WIN32
    void PrintLastError(const char* msg) {
        char* error;
        if (FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                           NULL,
                           ::GetLastError(),
                           MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                           (LPSTR)&error,
                           0,
                           NULL)) {
            fprintf(stderr, "%s: %s\n", msg, error);
            fflush(stderr);
        }
    }
#endif

    enum class MemTrackMode : uint8_t {
        Off = 0,
        Track = 1,
        Guard = 2,

        Max = Guard,
    };
    const MemTrackMode MemTrack = [] {
        const char* track = GetEnv("PEP_MEMTRACK");
        uint32_t value = track ? std::strtoul(track, nullptr, 10) : 0;
        value = std::min(value, uint32_t(MemTrackMode::Max));
        return MemTrackMode(value);
    }();

    void* Alloc(uint64_t size) {
#if _WIN32
        void* mem = VirtualAlloc(nullptr, size, MEM_COMMIT, PAGE_READWRITE);
        if (!mem) {
            PrintLastError("VirtualAlloc failed");
            abort();
        }
        return mem;
#else
        void* mem = malloc(size);
        return mem;
#endif
    }

    void Free(void* mem) {
        Header* base = (Header*)mem;
#if _WIN32
        if (!VirtualFree(mem, 0, MEM_RELEASE)) {
            PrintLastError("VirtualFree failed");
            panic("Memory corruption or Alloc/Free mismatch detected");
        }
#else
        free(mem);
#endif
    }

    void Unguard(void* mem) {
        Header* base = (Header*)mem;
#if _WIN32
        // no-op, VirtualFree can release protected pages
#endif
    }

    void Guard(void* mem) {
        Header* base = (Header*)mem;
        {
            std::unique_lock lock(MemLock);
            if (GuardPages.tail == MAX_GUARD_PAGES) {
                GuardPages.tail = 0;
            }
            if (auto* page = GuardPages.pages[GuardPages.tail]) {
                Unguard(page);
                Free(page);
            }
            GuardPages.pages[GuardPages.tail++] = base;
        }

#if _WIN32
        DWORD oldProtection = 0;
        if (!VirtualProtect(base, base->size, PAGE_NOACCESS, &oldProtection)) {
            PrintLastError("VirtualProtect failed");
        }
#endif
    }

    void PepExit() {
        std::call_once(Exited, [&] {
            std::unique_lock lock(MemLock);
            for (size_t idx = 0; idx < GuardPages.tail; ++idx) {
                void* page = GuardPages.pages[idx];
                Free(page);
            }
        });
    }

    void PepInit() {
        std::atexit(PepExit);
        std::at_quick_exit(PepExit);
    }
} // namespace

#define MEMTRACK(...)                                                                                                  \
    do {                                                                                                               \
        if (MemTrack != MemTrackMode::Off) {                                                                           \
            __VA_ARGS__                                                                                                \
        }                                                                                                              \
    } while (false)

extern "C" {
    void trace_region(const void* ptr, size_t size, const char* name) {
        const size_t* base = (size_t*)ptr;
        size_t region_size = size;
        if (auto rem = (size % sizeof(size_t)))
            region_size += sizeof(size_t) - rem;
        auto width = printf("%s: %p -> %016zX\n", name, ptr, base ? *base : 0);
        if (base) {
            for (int idx = 0; idx < (region_size / sizeof(size_t)); ++idx) {
                auto addr = base + idx;
                const char* str = (char*)addr;
                printf("%*c%0*zX ", width - 16 - 1, ' ', 16, *addr);
                for (int i = 0; i < sizeof(size_t); ++i) {
                    printf("%c", (i < size) ? (str[i] ? str[i] : '0') : '.');
                }
                printf("\n");
            }
        }
        fflush(stdout);
    }

    void trace_ptr(const void* ptr, const char* name) {
        trace_region(ptr, sizeof(size_t), name);
    }

    void trace_int(int64_t value, const char* name) {
        printf("%s: %" PRId64 "\n", name, value);
        fflush(stdout);
    }

    void _pep_assert(bool condition, const char* message) {
        if (AssertFn) {
            AssertFn(condition, message);
            return;
        }
        fprintf(stderr, "assert failed: %s\n", message);
        fflush(stderr);
        assert(condition);
    }

    void* _pep_malloc(size_t size) {
        static uint32_t AllocId = 0;
        std::call_once(Initialized, PepInit);

        MEMTRACK(size += sizeof(Header););

        void* ptr = Alloc(size);

        MEMTRACK(size -= sizeof(Header); Header* header = (Header*)ptr; header->size = size; header->id = AllocId++;
                 ptr = header + 1;
                 printf("_pep_malloc: %p(%u), size: %u\n", ptr, header->id, header->size););

        memset(ptr, 0, size);
        return ptr;
    }

    void* _pep_realloc(void* ptr, size_t prevSize, size_t newSize) {
        // When tracking memory/using guard pages, we need to do realloc manually since VirtualAlloc and friends
        // don't support realloc operations
        void* prevMem = ptr;
        void* newMem = Alloc(newSize);
        if (prevMem) {
            memcpy((uint8_t*)newMem, prevMem, std::min(prevSize, newSize));
            Free(prevMem);
        }
        if (newSize > prevSize) {
            memset((uint8_t*)newMem + prevSize, 0, newSize - prevSize);
        }

        return newMem;
    }

    void _pep_free(void* ptr) {
        MEMTRACK({
            Header* base = (Header*)ptr - 1;
            printf("_pep_free: %p(%u), size: %u\n", ptr, base->id, base->size);
            trace_region(ptr, base->size, "_pep_free");
            ptr = base;

            if (MemTrack == MemTrackMode::Guard) {
                Guard(base);
                return;
            };
        });

        Free(ptr);
    }

    size_t _pep_utf8_length(const char* str) {
        size_t count = 0;
        for (size_t i = 0; str[i]; ++i, ++count) {
            uint8_t c = (uint8_t)str[i];
            if (c <= 127)
                i += 0;
            else if ((c & 0xE0) == 0xC0)
                i += 1;
            else if ((c & 0xF0) == 0xE0)
                i += 2;
            else if ((c & 0xF8) == 0xF0)
                i += 3;
            else
                return 0; // invalid utf8
        }
        return count;
    }

    size_t _pep_utf8_size(const char* str, uint32_t chars) {
        if (chars == 0) {
            return strlen(str);
        }

        size_t count = 0;
        size_t charIdx = 0;
        for (size_t i = 0; str[i] && charIdx < chars; ++i, ++charIdx) {
            uint8_t c = (uint8_t)str[i];
            size_t size = 0;
            if (c <= 127)
                size = 1;
            else if ((c & 0xE0) == 0xC0)
                size = 2;
            else if ((c & 0xF0) == 0xE0)
                size = 3;
            else if ((c & 0xF8) == 0xF0)
                size = 4;
            else
                return 0; // invalid utf8

            count += size;
            i += size - 1;
        }
        return count;
    }

    bool _pep_utf8_compare(const char* a, const char* b, size_t size) {
        int diff = (size == 0) ? strcmp(a, b) : strncmp(a, b, size);
        return diff == 0;
    }
}
