## The machine the program runs on: its operating system, processor,
## memory and name.

import async;
import "sys_posix";
import "sys_wasi";
import "sys_windows";

## An operating system Pepper runs on, with the names `[Target(OS(...))]`
## uses.
##
## @see system_os
export enum OperatingSystem {
    ## Linux.
    Linux,
    ## macOS.
    Mac,
    ## Windows.
    Windows,
    ## WASI: a WebAssembly runtime such as wasmtime (`--target wasm32-wasip1`).
    Wasi,
    ## iOS and iPadOS, on a device or in the simulator (`--target
    ## aarch64-apple-ios`). `[Target(OS(Mac))]` covers it too.
    IOS,
    ## Android (`--target aarch64-linux-android`). `[Target(OS(Linux))]`
    ## covers it too.
    Android,
}

## Returns the operating system the program was built for.
##
## @returns the operating system
## @example
##     import os;
##
##     main(): int {
##         var executable = os.system_os() == os.OperatingSystem.Windows ? "tool.exe" : "tool";
##         print(executable);
##         return 0;
##     }
export system_os(): OperatingSystem {
    return _os_sys_os();
}

## Returns the name of the operating system the program was built for, in
## lowercase: `"linux"`, `"macos"`, `"windows"`, `"wasi"`, `"ios"` or
## `"android"`, for printing and for file and directory names.
##
## @returns the operating system's name
## @see system_os
export system_name(): String {
    match (system_os()) {
        Linux => { return "linux"; }
        Mac => { return "macos"; }
        Windows => { return "windows"; }
        Wasi => { return "wasi"; }
        IOS => { return "ios"; }
        Android => { return "android"; }
    }
}

## Returns the operating system's version: the kernel release on Linux
## (`uname -r`, such as `6.8.0-45-generic`), the product version on macOS
## (`sw_vers -productVersion`, such as `14.5`), and the major, minor and
## build numbers on Windows (such as `10.0.22631`). WASI does not report
## one.
##
## @returns the version, or an empty String when the system does not report
##   it
export system_version(): String {
    return _os_sys_version();
}

## Returns the processor architecture the program was built for: `"x64"`,
## `"aarch64"` or `"wasm32"`, the names `[Target(Arch(...))]` uses.
##
## @returns the architecture's name
[Target(Arch(x64))]
export architecture(): String {
    return "x64";
}

## Returns the processor architecture the program was built for: `"x64"`,
## `"aarch64"` or `"wasm32"`, the names `[Target(Arch(...))]` uses.
##
## @returns the architecture's name
[Target(Arch(aarch64))]
export architecture(): String {
    return "aarch64";
}

## Returns the processor architecture the program was built for: `"x64"`,
## `"aarch64"` or `"wasm32"`, the names `[Target(Arch(...))]` uses.
##
## @returns the architecture's name
[Target(Arch(wasm32))]
export architecture(): String {
    return "wasm32";
}

## Returns the machine's host name, as `hostname` prints it (on Windows its
## DNS host name). WASI does not report one.
##
## @returns the host name, or an empty String when the system does not
##   report it
export hostname(): String {
    return _os_sys_hostname();
}

## Returns the number of logical processors: every hardware thread, so a
## core with hyperthreading counts two or more times. The same as
## `async.logical_cpus()`.
##
## @returns the number of logical processors, at least 1
## @see physical_cpus
export logical_cpus(): ulong {
    return async.logical_cpus();
}

## Returns the number of physical processor cores: hardware threads that
## share a core count once. The same as `async.physical_cpus()`.
##
## @returns the number of physical cores, at least 1 and at most
##   `logical_cpus()`
## @see logical_cpus
export physical_cpus(): ulong {
    return async.physical_cpus();
}

## Returns the machine's physical memory in bytes. Inside a virtual
## machine this is what the guest sees; a container's memory limit is not
## taken into account. WASI does not report it.
##
## @returns the total physical memory in bytes, or 0 when the system does
##   not report it
export total_memory(): ulong {
    return _os_sys_total_memory();
}

## Returns the size of a page of virtual memory in bytes: the unit the
## operating system maps memory in, usually 4096 (16384 on Apple silicon;
## 65536, WebAssembly's page, on WASI).
##
## @returns the page size in bytes
export page_size(): ulong {
    return _os_sys_page_size();
}
