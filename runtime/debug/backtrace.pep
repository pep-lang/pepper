## Capturing the call stack (`capture`, `Backtrace`) and resolving it to
## functions and source lines (`StackFrame`).
##
## Capturing only records return addresses, so it is cheap enough to do
## whenever something might need reporting later. The addresses are
## resolved, from the program's symbol table and its debug info, only when
## `Backtrace.frames()` or `to_string()` asks for them.
##
## A function name needs the program's symbol table, which every build
## keeps unless the executable is stripped. A file, line and column need
## the debug info a `-g` build carries:
##
## - **Linux:** the executable's ELF symbol table and DWARF line table.
## - **macOS:** the executable's symbol table, and the DWARF line table of
##   the `.dSYM` bundle a `-g` build writes beside it.
## - **Windows:** DbgHelp, which reads the `.pdb` every build writes beside
##   the executable: function names only, or with `-g` source lines too (no
##   columns).
## - **WASI:** a WebAssembly program cannot walk its stack, so a backtrace
##   is empty.
##
## Frames inside the runtime's own capture and panic code are left out, and
## so are the C runtime's frames below `main`. A function the optimizer
## inlined into its caller has no frame of its own.

import "dwarf";
import "symbols_elf";
import "symbols_macho";
import "sys_posix";
import "sys_wasi";
import "sys_windows";

## One call on the stack: where it returns to, and the function and source
## position that address belongs to.
##
## @example
##     import debug;
##
##     main(): int {
##         var frame = debug.capture().frames()[0];
##         assert(frame.function == "main", "the innermost frame is main");
##         print(frame.to_string());   # main at main.pep:4:21 in a -g build
##         return 0;
##     }
export struct StackFrame {
    ## The return address: the instruction the call returns to.
    var address: ulong;
    ## The function's name, such as `main` or `Point.length`; empty when the
    ## program has no symbol for the address.
    var function: String;
    ## The source file, as it was named to the compiler; empty without debug
    ## info.
    var file: String;
    ## The 1-based source line of the call; 0 without debug info.
    var line: int;
    ## The 1-based source column of the call; 0 when unknown.
    var column: int;

    ## Creates a StackFrame for `address`, with no function or source
    ## position yet.
    ##
    ## @param address the return address
    construct(address: ulong = 0) {
        this.address = address;
        function = "";
        file = "";
        line = 0;
        column = 0;
    }

    ## Returns the frame as text: `function at file:line:column`, with the
    ## parts that are unknown left out, and the address in hexadecimal when
    ## the function is unknown.
    ##
    ## @returns the frame as text
    to_string(): String {
        var text = function.is_empty ? $"0x{address:x}" : function;
        if (!file.is_empty) {
            text = $"{text} at {file}";
            if (line > 0) {
                text = $"{text}:{line}";
                if (column > 0) {
                    text = $"{text}:{column}";
                }
            }
        }
        return text;
    }
}

extend StackFrame with ToString;

## The call stack at the point `capture()` ran, as return addresses,
## innermost first.
##
## @example
##     import debug;
##
##     main(): int {
##         var trace = debug.capture();
##         for (var frame in trace.frames()) {
##             print(frame.to_string());
##         }
##         return 0;
##     }
export struct Backtrace {
    ## The return address of each call, innermost first, as captured: it
    ## includes the frames of `capture` itself, which `frames()` leaves out.
    var addresses: Array<ulong>;

    ## Creates an empty Backtrace. Use `capture()` to record the stack.
    construct() {
        addresses = Array<ulong>();
    }

    ## Resolves each return address to its function and source position.
    ## Runs in time proportional to the program's symbol and line tables,
    ## which it reads each call.
    ##
    ## Leaves out the frames of `capture` and of the runtime's panic code at
    ## the top, and the C runtime's frames below `main`.
    ##
    ## @returns the frames, innermost first
    frames(): Array<StackFrame> {
        var all = Array<StackFrame>();
        for (var address in addresses) {
            all.append(StackFrame(address));
        }
        _debug_sys_symbolize(all);
        ulong first = 0;
        while (first < all.count && _debug_is_internal(all[first].function)) {
            first = first + 1;
        }
        var frames = Array<StackFrame>();
        ulong index = first;
        while (index < all.count) {
            frames.append(all[index]);
            if (all[index].function == "main") {
                break;
            }
            index = index + 1;
        }
        return frames;
    }

    ## Returns the frames as text, one per line, each numbered and indented
    ## (`  0: main at main.pep:4:5`), with a newline after the last.
    ##
    ## @returns the frames as text
    to_string(): String {
        var text = StringBuilder();
        ulong index = 0;
        for (var frame in frames()) {
            text.append($"  {index}: {frame.to_string()}\n");
            index = index + 1;
        }
        return text.to_string();
    }
}

extend Backtrace with ToString;

## Records the call stack: the return address of every call that led here.
## Cheap: the addresses are resolved only when `Backtrace.frames()` or
## `to_string()` asks for them.
##
## Records at most 128 calls, the innermost ones. On WASI the Backtrace is
## empty.
##
## @returns the stack, innermost call first
## @example
##     import debug;
##
##     main(): int {
##         var trace = debug.capture();
##         print(trace.to_string());
##         return 0;
##     }
export capture(): Backtrace {
    var trace = Backtrace();
    _debug_sys_capture(trace.addresses, 128);
    return trace;
}

## Writes the current call stack to standard error, a line per frame, after
## a `backtrace:` line: what a panic prints after its message.
##
## A panic prints it in a build without `-O`. Set the `PEPPER_BACKTRACE`
## environment variable to `1` to print it in an optimized build too, or to
## `0` to never print it.
##
## @example
##     import debug;
##
##     main(): int {
##         debug.print_backtrace();
##         return 0;
##     }
export print_backtrace() {
    _debug_write_backtrace(capture());
}

_debug_write_backtrace(trace: Backtrace) {
    var text = $"backtrace:\n{trace.to_string()}";
    _pep_write_error(text.c_str());
}

# Called by `_pep_panic` after it prints the message: the backtrace, when
# PEPPER_BACKTRACE or the build (`_pep_backtrace_default`) asks for one. A
# panic while printing it (a bug in the symbolizer) prints none, rather
# than recursing.
export _debug_panic_backtrace() {
    if (!_debug_backtrace_wanted() || !_pep_enter_backtrace()) {
        return;
    }
    _debug_write_backtrace(capture());
}

_debug_backtrace_wanted(): bool {
    __ptr<char> setting = _debug_getenv("PEPPER_BACKTRACE");
    if (setting == __null || setting[0] == 0) {
        return _pep_backtrace_default();
    }
    return !(setting[0] == '0' && setting[1] == 0);
}

extern char* getenv(char* name);

_debug_getenv(name: String): __ptr<char> {
    return getenv(name.c_str());
}

# The runtime functions a captured stack starts with: `capture` and the
# platform call under it, and the panic path that prints a backtrace.
_debug_is_internal(function: String): bool {
    if (function.starts_with("_debug_") || function.starts_with("_pep_")) {
        return true;
    }
    return function == "capture" || function == "print_backtrace" || function == "panic" || function == "assert";
}

# The readable name of a symbol: `_P` names undo the compiler's escaping
# (see `symbol_name` in pepper-codegen's partition.rs), then a name's file
# (`helper@io/file`) and overload suffix (`panic$1`) are dropped:
# `_PArray_3cint_3e.count` is `Array<int>.count`.
export _debug_demangle(symbol: String): String {
    var name = symbol;
    if (symbol.starts_with("_P")) {
        var bytes = symbol.c_str();
        __ptr<char> decoded = _pep_malloc(symbol.size);
        ulong size = 0;
        ulong index = 2;
        while (index < symbol.size) {
            var c = bytes[index];
            if (c == '_' && index + 1 < symbol.size && bytes[index + 1] == '_') {
                decoded[size] = '_';
                index = index + 2;
            } else if (c == '_' && index + 2 < symbol.size) {
                var high = _pep_hex_digit(bytes[index + 1] as int);
                var low = _pep_hex_digit(bytes[index + 2] as int);
                if (high < 0 || low < 0) {
                    _pep_free(decoded);
                    return symbol;
                }
                decoded[size] = (high * 16 + low) as char;
                index = index + 3;
            } else {
                decoded[size] = c;
                index = index + 1;
            }
            size = size + 1;
        }
        name = String(decoded, size);
        _pep_free(decoded);
    }
    return _debug_drop_suffixes(name);
}

# `name` without each `@file` and `$overload` part: each runs to the next
# `.`, `<`, `>`, `,` or space.
_debug_drop_suffixes(name: String): String {
    if (name.find("@") < 0 && name.find("$") < 0) {
        return name;
    }
    var text = StringBuilder();
    var bytes = name.c_str();
    var skipping = false;
    ulong index = 0;
    while (index < name.size) {
        var c = bytes[index];
        if (c == '@' || c == '$') {
            skipping = true;
        } else if (c == '.' || c == '<' || c == '>' || c == ',' || c == ' ') {
            skipping = false;
        }
        if (!skipping) {
            text.append(String(bytes + index, 1));
        }
        index = index + 1;
    }
    return text.to_string();
}
