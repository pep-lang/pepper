# Calling C

Pepper programs can call functions written in C: the C standard library, your
operating system's API, or any other library with a C interface. You declare
the C function's prototype with `extern`, make sure the library that defines it
is linked, and then call it like any Pepper function.

## Declaring a C function

An `extern` declaration is a C prototype, written the way C writes it: the
return type, the name, and the parameter types, each followed by a parameter
name. It has no body.

```pepper
extern ulong strlen(char* s);
extern int strcmp(char* a, char* b);
extern void* malloc(ulong size);
extern void free(void* p);
```

After that, `strlen("hello")` calls the C library's `strlen`. The compiler
does not check your prototype against any C header, so it must match the real
C function exactly. A wrong parameter or return type compiles, and then passes
or reads the wrong bits when the program runs.

Match C types with Pepper types of the same size:

| C | Pepper |
|---|---|
| `char`, `signed char`, `unsigned char` | `char` or `i8`, `u8` or `byte` |
| `short`, `unsigned short` | `short` or `i16`, `ushort` or `u16` |
| `int`, `unsigned int` | `int` or `i32`, `uint` or `u32` |
| `long long`, `unsigned long long`, `int64_t`, `size_t` (64-bit) | `long` or `i64`, `ulong` or `u64` |
| `float`, `double` | `float`, `double` |
| `T*` | `T*` in the prototype |

Pepper's `long` is always 64 bits. C's `long` is 64 bits on Linux and macOS but
32 bits on Windows, so a C function that takes `long` needs a different
prototype per platform (see [`[LinkName]`](#binding-to-a-different-symbol-name)
below for an example).

Some things to know about `extern` declarations:

- The prototype uses C syntax only. The `name(parameter: type): type` form that
  Pepper functions use is a parse error on an extern, and `__ptr<T>` as a
  parameter type is an error too: write `char*`, not `__ptr<char>`.
- An extern is private to its file, like every declaration. Write
  `export extern ...` to let files that import this one call it (see
  [Visibility](visibility.md)).
- Several files may declare the same extern, since every declaration names the
  same C function. The runtime already declares `malloc`, `free` and a few
  others privately, and your program can declare them again.
- An extern is linked by name. If no linked library defines it, the program
  compiles and then fails to link, with the linker reporting an undefined symbol. See
  [Linking](linking.md) for how to add libraries.

## Passing strings

Pepper's [`String`](../reference/string.md) is a reference-counted object, not
a C string, so a `String` value cannot be passed where C expects `char*`.

- A **string literal** passed to an extern is passed as a NUL-terminated C
  string, with no allocation: `strlen("hello")` is 5.
- A **`String` value** is passed with `c_str()`, which returns the String's
  NUL-terminated buffer as a `__ptr<char>`. The pointer belongs to the String:
  it is valid until the String is destroyed or grows (for example with
  `append` or `+=`). An empty `String()` has no buffer, so its `c_str()` is
  `__null`; check before you pass it to a C function that does not accept
  `NULL`.
- To turn a C string back into a `String`, pass the pointer to the
  constructor: `String(p)` copies a NUL-terminated C string, and
  `String(p, size)` copies `size` bytes. If you already know the number of
  code points, pass it as a third argument:
  `String(p, size, String.length_of(p, size))`. The constructor copies the
  bytes, so you still own (and may free) the C buffer.

```pepper
{{#include ../../examples/c-strings.pep}}
```

Passing a `String` value directly to an extern's `char*` parameter is an error:

```text
main.pep:4:19: error: cannot pass 'String' to parameter 1 of extern 'strlen' of type 'char*'; pass its 'c_str()'
    4 |     return strlen(name) as int;
      |                   ^~~~
```

## Variadic functions

A C function with a variable argument list, such as `printf` or `snprintf`,
ends its prototype with `...` after at least one named parameter:

```pepper
extern int snprintf(char* buffer, ulong size, char* format, ...);
```

The call uses the C calling convention for variadic functions, which differs
from a plain call on some targets (such as macOS on Apple silicon). Each
argument past the named ones gets C's default argument promotions: integers
narrower than `int` widen to `int`, and `float` widens to `double`. Match your
format string to the promoted type: `%d` for a `u8`, `%f` for a `float`, and
`%lld` (not `%ld`) for a `long`, because C's `long` is 32 bits on Windows.

`...` must come last and must follow a named parameter: `extern int f(...);`
is a parse error.

```pepper
{{#include ../../examples/c-variadic.pep}}
```

On Windows, the C runtime defines `snprintf` and its relatives inline in its
headers, so the linkable symbols live in a separate library,
`legacy_stdio_definitions`. The example links it with `[Link]` on Windows only.

## Pointers

C code deals in raw pointers, and Pepper has a raw pointer type for talking to
it: `__ptr<T>`, such as `__ptr<void>`, `__ptr<char>` or `__ptr<__ptr<int>>`.
A `void*` returned by an extern is a `__ptr<void>` in Pepper, and a
`__ptr<T>` can be passed to an extern that takes a C pointer.

A pointer supports these operations:

| Operation | Meaning |
|---|---|
| `p[i]` | reads or writes the element `i` places from `p`; its type is `T`, so `var v = p[i]` declares a `T` |
| `p + n` | the address `n` elements after `p` (`n` bytes for `__ptr<void>`) |
| `p == __null`, `p != __null` | compares with the null pointer |
| `p == q`, `p != q` | compares two addresses (a pointer also compares with an integer address) |
| `p as ulong`, `p as long` | the address as an integer |
| `p as __ptr<U>` | the same address, seen as pointing at `U` |

`__null` is the null pointer. `sizeof<T>()` gives the size of a type in bytes,
which you need to allocate memory for C.

`T*` spelling is for extern prototypes only, since they mirror C. Everywhere
else (parameters, return types, struct fields, locals, globals, type aliases,
generic arguments and casts) you write `__ptr<T>`, and `T*` is a compile error:

```pepper
clear(p: void*, n: ulong) { }
```

```text
main.pep:1:10: error: C pointer syntax `void*` is only allowed in extern declarations; use `__ptr<void>`
    1 | clear(p: void*, n: ulong) { }
      |          ^~~~
```

```pepper
{{#include ../../examples/c-pointers.pep}}
```

Pointers are not reference-counted and nothing checks them: indexing past the
end of an allocation, using memory after `free`, or forgetting to `free` it
behaves exactly as it would in C. Keep raw pointers inside small functions or
structs that own the memory, and give the rest of your program ordinary Pepper
types.

## Passing a Pepper function to C

A Pepper [function value](function-types.md) is a Pepper object, not a C
function pointer. To hand a function to C as a callback, such as the
comparison function of `qsort`, take its address with
`__function_pointer(name)`. The result is a `__ptr<void>`:

```pepper
{{#include ../../examples/c-callbacks.pep}}
```

- The argument must name a free function, or a static method of the struct
  whose method uses it. Inside a generic struct the static method is the one
  for the current type arguments, which is how `ThreadLocal<T>` gives the
  operating system a destructor for its `T`.
- C calls the function with the C calling convention, so give it
  C-compatible parameter and return types: numbers and `__ptr<T>`. C knows
  nothing of reference counts, so a struct parameter or return value would
  not be counted correctly.
- A name that is not a function is reported as
  `use of undeclared identifier`.

## Binding to a different symbol name

`[LinkName("symbol")]` binds an extern to a C symbol whose name differs from
the declared one. Pepper code calls the extern by its declared name, and the
object file refers to `symbol`. Use it to give a C function a clearer name, to
avoid clashing with a Pepper name, or, together with
[`[Target]`](platform-selection.md), to bind one Pepper name to a different
symbol on each platform:

```pepper
{{#include ../../examples/c-link-name.pep}}
```

Real uses of the per-platform form include macOS on Intel, where the
64-bit-inode version of `stat` is named `stat$INODE64`:

```pepper
[Target(OS(Mac) && Arch(x64))] [LinkName("stat$INODE64")] extern int stat(char* path, void* buf);
[Target(OS(Mac) && Arch(aarch64))] extern int stat(char* path, void* buf);
```

`LinkName` takes exactly one non-empty string, and an extern may carry at most
one. Anything else is an error, such as:

```text
main.pep:1:34: error: LinkName on extern 'pep_abs' takes exactly one string: [LinkName("sym")]
    1 | [LinkName("a", "b")] extern long pep_abs(long v);
      |                                  ^~~~~~~
```

## Linking the library

A C function is only callable if the library that defines it is linked into
your program. The C library is always linked. For anything else, attach
`[Link("name")]` to the extern or pass `-l name` to the compiler. The
[Linking](linking.md) chapter covers both.

```pepper
[Target(OS(Windows))] [Link("gdi32")] extern ulong GetStockObject(int kind);
```

## Calling Pepper from C

Pepper builds executables, and there is no supported way yet for C code to
call Pepper functions. The parser accepts an `[Export]` attribute on a
function, intended to give it a C interface with object references passed as
opaque handles, but the compiler does not act on it yet: `[Export]` currently
has no effect.

Do not confuse `[Export]` with the `export` keyword, which makes a
declaration visible to other Pepper files (see [Visibility](visibility.md)).
