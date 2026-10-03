# Windows platform layer for debug: RtlCaptureStackBackTrace captures,
# DbgHelp resolves (from the `.pdb` every build writes beside the
# executable: public symbols only without `-g`), and OutputDebugStringW is the debugger channel. Every
# declaration carries [Target(OS(Windows))].

import "backtrace";

[Target(OS(Windows))]
extern ushort RtlCaptureStackBackTrace(uint skip, uint count, void* trace, uint* hash);
[Target(OS(Windows))]
extern void* GetCurrentProcess();
[Target(OS(Windows))]
extern uint GetModuleFileNameA(void* module, char* name, uint size);
[Target(OS(Windows))]
extern void OutputDebugStringW(ushort* text);
[Target(OS(Windows))]
extern int IsDebuggerPresent();
[Target(OS(Windows))]
extern int MultiByteToWideChar(uint code_page, uint flags, char* text, int size, ushort* wide, int wide_size);
[Target(OS(Windows))]
extern void Sleep(uint milliseconds);
[Target(OS(Windows))]
extern void memset(void* p, int c, ulong n);
[Target(OS(Windows))]
extern void* calloc(ulong count, ulong size);
[Target(OS(Windows))]
[Link("dbghelp")]
extern uint SymSetOptions(uint options);
[Target(OS(Windows))]
[Link("dbghelp")]
extern int SymInitialize(void* process, char* search_path, int invade);
[Target(OS(Windows))]
[Link("dbghelp")]
extern int SymFromAddr(void* process, ulong address, ulong* displacement, void* symbol);
[Target(OS(Windows))]
[Link("dbghelp")]
extern int SymGetLineFromAddr64(void* process, ulong address, uint* displacement, void* line);
[Target(OS(Windows))]
[Link("dbghelp")]
extern int SymRefreshModuleList(void* process);

[Target(OS(Windows))]
export _debug_sys_capture(addresses: Array<ulong>, limit: int) {
    __ptr<ulong> buffer = _pep_malloc((limit as ulong) * 8);
    var count = RtlCaptureStackBackTrace(0, limit as uint, buffer, __null) as ulong;
    ulong index = 0;
    while (index < count) {
        addresses.append(buffer[index]);
        index = index + 1;
    }
    _pep_free(buffer);
}

# DbgHelp is single-threaded: [0] is a spin lock around every call into
# it, [1] is 1 once SymInitialize has run (it stays initialized).
[Target(OS(Windows))]
const _debug_dbghelp_state: __ptr<int> = _debug_new_dbghelp_state();

# C's calloc, not _pep_malloc: the prelude imports this module, so this
# initializer runs before the prelude's own, which _pep_malloc needs. The
# memory lives as long as the process.
[Target(OS(Windows))]
_debug_new_dbghelp_state(): __ptr<int> {
    return calloc(2, 4);
}

# SYMBOL_INFO: SizeOfStruct (88 with its one-byte Name) at 0, MaxNameLen at
# 80, Name at 84.
const _DEBUG_SYMBOL_INFO_SIZE: ulong = 88;
const _DEBUG_SYMBOL_NAME_MAX: ulong = 512;
# IMAGEHLP_LINE64: SizeOfStruct at 0, LineNumber at 16, FileName at 24.
const _DEBUG_LINE_INFO_SIZE: ulong = 40;

[Target(OS(Windows))]
export _debug_sys_symbolize(frames: Array<StackFrame>) {
    var process = GetCurrentProcess();
    while (!__atomic_cmpxchg<int>(_debug_dbghelp_state, 0, 1)) {
        Sleep(0);
    }
    if (_debug_dbghelp_state[1] == 0) {
        # SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES. Not SYMOPT_UNDNAME: it
        # strips the leading '_' of a public symbol (all a build without -g
        # has), and `_debug_demangle` needs it to recognize a `_P` name.
        SymSetOptions(0x14);
        __ptr<char> path = _pep_malloc(1024);
        var length = GetModuleFileNameA(__null, path, 1024) as ulong;
        # Search the executable's folder, where the linker writes the .pdb.
        while (length > 0 && path[length - 1] != '\\' && path[length - 1] != '/') {
            length = length - 1;
        }
        path[length] = 0;
        if (SymInitialize(process, length > 0 ? path : __null, 1) != 0) {
            _debug_dbghelp_state[1] = 1;
        }
        _pep_free(path);
    } else {
        # Modules loaded since the last call.
        SymRefreshModuleList(process);
    }
    if (_debug_dbghelp_state[1] == 1) {
        __ptr<u8> symbol = _pep_malloc(_DEBUG_SYMBOL_INFO_SIZE + _DEBUG_SYMBOL_NAME_MAX);
        __ptr<u8> line = _pep_malloc(_DEBUG_LINE_INFO_SIZE);
        __ptr<ulong> displacement = _pep_malloc(8);
        for (var frame in frames) {
            # The call is one byte before the return address.
            var lookup = frame.address > 0 ? frame.address - 1 : 0;
            memset(symbol, 0, _DEBUG_SYMBOL_INFO_SIZE + _DEBUG_SYMBOL_NAME_MAX);
            __ptr<uint> symbol_size = unsafe_cast<__ptr<uint>>(symbol);
            symbol_size[0] = _DEBUG_SYMBOL_INFO_SIZE as uint;
            symbol_size[20] = _DEBUG_SYMBOL_NAME_MAX as uint;
            if (SymFromAddr(process, lookup, displacement, symbol) != 0) {
                frame.function = _debug_demangle(String(unsafe_cast<__ptr<char>>(symbol + 84)));
            }
            memset(line, 0, _DEBUG_LINE_INFO_SIZE);
            __ptr<uint> line_size = unsafe_cast<__ptr<uint>>(line);
            line_size[0] = _DEBUG_LINE_INFO_SIZE as uint;
            if (SymGetLineFromAddr64(process, lookup, unsafe_cast<__ptr<uint>>(displacement), line) != 0) {
                __ptr<int> line_number = unsafe_cast<__ptr<int>>(line + 16);
                frame.line = line_number[0];
                __ptr<__ptr<char>> file_name = unsafe_cast<__ptr<__ptr<char>>>(line + 24);
                __ptr<char> file = file_name[0];
                if (file != __null) {
                    frame.file = String(file);
                }
            }
        }
        _pep_free(displacement);
        _pep_free(line);
        _pep_free(symbol);
    }
    __atomic_store<int>(_debug_dbghelp_state, 0);
}

[Target(OS(Windows))]
export _debug_sys_output(text: String) {
    var line = text.ends_with("\n") ? text : $"{text}\n";
    # CP_UTF8; a size of -1 converts through the terminating NUL.
    var count = MultiByteToWideChar(65001, 0, line.c_str(), -1, __null, 0);
    if (count <= 0) {
        return;
    }
    __ptr<ushort> wide = _pep_malloc((count as ulong) * 2);
    MultiByteToWideChar(65001, 0, line.c_str(), -1, wide, count);
    OutputDebugStringW(wide);
    _pep_free(wide);
}

[Target(OS(Windows))]
export _debug_sys_debugger_attached(): bool {
    return IsDebuggerPresent() != 0;
}

[Target(OS(Windows))]
[Link(name = "llvm.debugtrap")]
extern void _debug_trap();

[Target(OS(Windows))]
export _debug_sys_breakpoint() {
    _debug_trap();
}
