# WASI platform layer for debug: a WebAssembly program cannot walk its own
# stack or be attached to, so capture records nothing and output goes to
# standard error.

import "backtrace";

[Target(OS(Wasi))]
_debug_sys_capture(addresses: Array<ulong>, limit: int) {}

[Target(OS(Wasi))]
_debug_sys_symbolize(frames: Array<StackFrame>): Array<StackFrame> {
    return frames;
}

[Target(OS(Wasi))]
_debug_sys_output(text: String) {
    var line = text.ends_with("\n") ? text : $"{text}\n";
    _pep_write_error(line.c_str());
}

[Target(OS(Wasi))]
_debug_sys_debugger_attached(): bool {
    return false;
}

[Target(OS(Wasi))]
_debug_sys_breakpoint() {}
