# POSIX (Linux, macOS) platform layer for debug. Every declaration carries
# [Target(OS(Linux) || OS(Mac))] or a narrower target; sys_windows.pep and
# sys_wasi.pep declare the same `_debug_sys_*` functions with the same
# signatures.

[Target(OS(Linux) || OS(Mac))]
extern int backtrace(void* buffer, int size);
[Target(OS(Linux) || OS(Mac))]
extern int open(char* path, int flags, ...);
[Target(OS(Linux) || OS(Mac))]
extern long read(int fd, void* buf, ulong n);
[Target(OS(Linux) || OS(Mac))]
extern int close(int fd);
[Target(OS(Mac))]
extern int getpid();
[Target(OS(Mac))]
extern int sysctl(int* name, uint count, void* value, ulong* size, void* new_value, ulong new_size);

# Appends up to `limit` return addresses, innermost first: glibc's and
# libSystem's `backtrace`, which unwinds through the tables every function
# carries (`uwtable`).
[Target(OS(Linux) || OS(Mac))]
export _debug_sys_capture(addresses: Array<ulong>, limit: int) {
    __ptr<ulong> buffer = _pep_malloc((limit as ulong) * 8);
    var count = backtrace(buffer, limit);
    ulong index = 0;
    while (index < count as ulong) {
        addresses.append(buffer[index]);
        index = index + 1;
    }
    _pep_free(buffer);
}

# Linux and macOS have no debugger channel apart from the program's own
# streams: debuggers show standard error.
[Target(OS(Linux) || OS(Mac))]
export _debug_sys_output(text: String) {
    var line = text.ends_with("\n") ? text : $"{text}\n";
    _pep_write_error(line.c_str());
}

# Linux: the `TracerPid:` line of /proc/self/status names the tracing
# process, 0 when there is none.
[Target(OS(Linux))]
export _debug_sys_debugger_attached(): bool {
    var fd = open("/proc/self/status".c_str(), 0);
    if (fd < 0) {
        return false;
    }
    var text = StringBuilder();
    __ptr<char> buffer = _pep_malloc(4096);
    while (true) {
        var count = read(fd, buffer, 4096);
        if (count <= 0) {
            break;
        }
        text.append(String(buffer, count as ulong));
    }
    _pep_free(buffer);
    close(fd);
    var status = text.to_string();
    var at = status.find("TracerPid:");
    if (at < 0) {
        return false;
    }
    var index = (at as ulong) + 10;
    var bytes = status.c_str();
    while (index < status.size && (bytes[index] == ' ' || bytes[index] == '\t')) {
        index = index + 1;
    }
    return index < status.size && bytes[index] != '0';
}

# macOS: `P_TRACED` in the process's `kinfo_proc` (Apple's technical Q&A
# QA1361): `kp_proc.p_flag` is the int at offset 32.
[Target(OS(Mac))]
export _debug_sys_debugger_attached(): bool {
    # CTL_KERN, KERN_PROC, KERN_PROC_PID, pid
    __ptr<int> name = _pep_malloc(16);
    name[0] = 1;
    name[1] = 14;
    name[2] = 1;
    name[3] = getpid();
    ulong info_size = 648;
    __ptr<u8> info = _pep_malloc(info_size);
    __ptr<ulong> size = _pep_malloc(8);
    size[0] = info_size;
    var traced = false;
    if (sysctl(name, 4, info, size, __null, 0) == 0) {
        var flags = unsafe_cast<__ptr<int>>(info + 32);
        # P_TRACED
        traced = (flags[0] & 0x800) != 0;
    }
    _pep_free(size);
    _pep_free(info);
    _pep_free(name);
    return traced;
}

[Target(OS(Linux) || OS(Mac))]
[Link(name = "llvm.debugtrap")]
extern void _debug_trap();

[Target(OS(Linux) || OS(Mac))]
export _debug_sys_breakpoint() {
    _debug_trap();
}
