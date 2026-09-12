extern void trace_region(void* ptr, ulong size, char* msg);
extern void trace_ptr(void* ptr, char* msg);
extern void trace_int(long num, char* msg);

extern void* _pep_malloc(ulong size);
extern void _pep_free(void* ptr);
extern void* _pep_realloc(void* ptr, ulong prevSize, ulong newSize);
extern void panic(char* msg);
