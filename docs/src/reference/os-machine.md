<!-- Generated from runtime/os/machine.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Machine

The machine the program runs on: its operating system, processor,
memory and name.

Source: `runtime/os/machine.pep`

## OperatingSystem

```pepper
enum OperatingSystem
```

An operating system Pepper runs on, with the names `[Target(OS(...))]`
uses.

**See also**
- `system_os`

### Cases

#### Linux

```pepper
Linux
```

Linux.

#### Mac

```pepper
Mac
```

macOS.

#### Windows

```pepper
Windows
```

Windows.

#### Wasi

```pepper
Wasi
```

WASI: a WebAssembly runtime such as wasmtime (`--target wasm32-wasip1`).

## system_os

```pepper
system_os(): OperatingSystem
```

Returns the operating system the program was built for.

**Returns**
- the operating system

**Example**
```pepper
import os;

main(): int {
    var executable = os.system_os() == os.OperatingSystem.Windows ? "tool.exe" : "tool";
    print(executable);
    return 0;
}
```

## system_name

```pepper
system_name(): String
```

Returns the name of the operating system the program was built for, in
lowercase: `"linux"`, `"macos"`, `"windows"` or `"wasi"`, for printing
and for file and directory names.

**Returns**
- the operating system's name

**See also**
- `system_os`

## system_version

```pepper
system_version(): String
```

Returns the operating system's version: the kernel release on Linux
(`uname -r`, such as `6.8.0-45-generic`), the product version on macOS
(`sw_vers -productVersion`, such as `14.5`), and the major, minor and
build numbers on Windows (such as `10.0.22631`). WASI does not report
one.

**Returns**
- the version, or an empty String when the system does not report it

## architecture

```pepper
[Target(Arch(x64))] architecture(): String
```

Returns the processor architecture the program was built for: `"x64"`,
`"aarch64"` or `"wasm32"`, the names `[Target(Arch(...))]` uses.

**Returns**
- the architecture's name

## architecture

```pepper
[Target(Arch(aarch64))] architecture(): String
```

Returns the processor architecture the program was built for: `"x64"`,
`"aarch64"` or `"wasm32"`, the names `[Target(Arch(...))]` uses.

**Returns**
- the architecture's name

## architecture

```pepper
[Target(Arch(wasm32))] architecture(): String
```

Returns the processor architecture the program was built for: `"x64"`,
`"aarch64"` or `"wasm32"`, the names `[Target(Arch(...))]` uses.

**Returns**
- the architecture's name

## hostname

```pepper
hostname(): String
```

Returns the machine's host name, as `hostname` prints it (on Windows its
DNS host name). WASI does not report one.

**Returns**
- the host name, or an empty String when the system does not report it

## logical_cpus

```pepper
logical_cpus(): ulong
```

Returns the number of logical processors: every hardware thread, so a
core with hyperthreading counts two or more times. The same as
`async.logical_cpus()`.

**Returns**
- the number of logical processors, at least 1

**See also**
- `physical_cpus`

## physical_cpus

```pepper
physical_cpus(): ulong
```

Returns the number of physical processor cores: hardware threads that
share a core count once. The same as `async.physical_cpus()`.

**Returns**
- the number of physical cores, at least 1 and at most `logical_cpus()`

**See also**
- `logical_cpus`

## total_memory

```pepper
total_memory(): ulong
```

Returns the machine's physical memory in bytes. Inside a virtual
machine this is what the guest sees; a container's memory limit is not
taken into account. WASI does not report it.

**Returns**
- the total physical memory in bytes, or 0 when the system does not report it

## page_size

```pepper
page_size(): ulong
```

Returns the size of a page of virtual memory in bytes: the unit the
operating system maps memory in, usually 4096 (16384 on Apple silicon;
65536, WebAssembly's page, on WASI).

**Returns**
- the page size in bytes
