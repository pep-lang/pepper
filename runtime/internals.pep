
use support;

@extern void* malloc(ulong size);
@extern void* realloc(void* ptr, ulong size);
@extern void free(void* ptr);

void release<T>(T t) {
    trace_ptr(t, "release<T>");
    t.__release();
}

# release specializations for integral types
void release<int>(int i) {}
void release<uint>(uint ui) {}
void release<bool>(bool b) {}
void release<long>(long l) {}
void release<ulong>(ulong ul) {}
void release<float>(float f) {}
void release<double>(double d) {}

void assert(bool condition, __ptr<char> msg) {
    if (!condition) {
        panic(msg);
    }
}
