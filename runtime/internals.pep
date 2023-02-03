
@extern void* malloc(ulong size);
@extern void* realloc(void* ptr, ulong size);
@extern void free(void* ptr);

void release<T>(T t) {
    trace_ptr(t, "release<T>");
    t.__release();
}

void release<int>(int i) {}
