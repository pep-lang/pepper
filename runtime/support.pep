extern void trace_region(void* ptr, ulong size, char* msg);
extern void trace_ptr(void* ptr, char* msg);
extern void trace_int(long num, char* msg);

extern void* _pep_malloc(ulong size);
extern void _pep_free(void* ptr);
extern void* _pep_realloc(void* ptr, ulong prevSize, ulong newSize);
extern void _pep_swap_refs(void* p, ulong stride, ulong i, ulong j);
extern void panic(char* msg);

extern ulong _pep_utf8_length(char* str);
extern ulong _pep_utf8_size(char* str, uint chars);
extern bool _pep_utf8_compare(char* a, char* b, ulong size);
extern long _pep_utf8_find(void* haystack, ulong haystackSize, void* needle, ulong needleSize);
extern ulong _pep_utf8_char_offset(char* data, ulong size, ulong chars);
extern ulong _pep_hash_bytes(void* data, ulong length);
