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
prototype per platform (see [`[Link(name = ...)]`](#binding-to-a-different-symbol-name)
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
  string, with no allocation: `strlen("hello")` is 5. The same is true
  wherever a literal flows into a `__ptr<char>`, `__ptr<u8>`, or
  `__ptr<void>` in Pepper code (a variable, field, argument, or return
  value), so `String("hello")` copies the literal's five bytes.
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
  bytes, so you still own (and may free) the C buffer. A C string is never
  passed or stored where a `String` is expected without this copy: that is
  an error.

```pepper
{{#include ../../examples/c-strings.pep}}
```

Passing a `String` value directly to an extern's `char*` parameter is an error:

```text
main.pep:4:19: error: cannot pass 'String' to parameter 1 of extern 'strlen' of type 'char*'; pass its 'c_str()'
    4 |     return strlen(name) as int;
      |                   ^~~~
```

The reverse is an error too: a `char*` (or any raw pointer, `void*`
included) is never a `String`, so passing one where a `String` is expected,
assigning it to a `String` variable, or returning it as one is rejected. Copy
it into a String with `String(p)` first:

```text
main.pep:3:19: error: cannot pass a value of type '__ptr<char>' as argument 2 of 'assert', which has type 'String'; use 'String(...)' to copy a C string
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
| `p as __ptr<void>`, `v as __ptr<T>` | the same address, to and from `__ptr<void>` |
| `unsafe_cast<__ptr<U>>(p)` | the same address, seen as pointing at `U` |
| `unsafe_cast<ulong>(p)`, `unsafe_cast<__ptr<T>>(n)` | the address as an integer, and back |

`as` converts a pointer only to and from `__ptr<void>`, like `static_cast` in
C++. Any other pointer conversion reinterprets memory, so it is spelled
`unsafe_cast` (see [Reinterpreting with
`unsafe_cast`](types-and-variables.md#reinterpreting-with-unsafe_cast)).

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

## Owning a C resource: `Handle<T>`

A C library hands out objects that it frees with a function of its own
(`fclose`, `free`, `LLVMDisposeModule`). Pepper's reference counting does
not know about them, so the runtime's `Handle<T>` ties one to Pepper's
lifetimes, like C#'s `SafeHandle`: it holds the raw value and a release
function, and calls the function once, when the last reference to the
handle goes away.

```pepper
{{#include ../../examples/c-handle.pep}}
```

- `Handle<T>(value, release)` takes ownership of `value`. `T` is usually
  `__ptr<void>` or an integer descriptor.
- `value` reads the raw value, to pass to C.
- A handle is a reference, so copies share the resource; it is released
  when the last copy goes away. Keep it in a field of the struct that
  wraps the resource, as `Buffer` does.
- `release()` frees the resource early, and `detach()` gives it back
  without freeing it. Either way the release function never runs again,
  and `is_owned()` becomes false.
- `release` is a function value, so a closure may capture what the release
  needs. A captured reference stays alive until the release runs, which is
  how a C object that must not outlive its parent (an LLVM module and its
  context) keeps the parent alive.

## Passing a Pepper function to C

A Pepper [function value](function-types.md) is a reference-counted object,
not a C function pointer. For C, Pepper has a separate type,
`extern (P...) => R`: the address of a function that C calls with the C
calling convention. Declare a callback parameter of a C function with it,
and pass a named function, or a closure that captures nothing:

```pepper
{{#include ../../examples/c-callbacks.pep}}
```

- **What converts.** A named free function, a static method
  (`Order.descending`), or a closure literal that captures nothing, whose
  parameter and return types match the C function pointer type exactly. A
  closure literal takes its parameter types from the type, as it does from
  any function type.
- **Nothing captured.** C calls the function with its arguments alone, so a
  closure that captures a value, or a bound method (`p.get`), cannot
  convert:

  ```text
  main.pep:4:43: error: closure passed as C function pointer type 'extern (void*, void*) => int' captures 'bias'; a C function pointer cannot hold captured values
      4 |     qsort(_pep_malloc(4), 0, 4, (a, b) => bias);
        |                                           ^~~~
  main.pep:3:9: note: pass what the callback needs through the C function's context argument instead
      3 |     var bias = 1;
        |         ^~~~
  ```

  Most C APIs that take a callback also take a `void*` context argument that
  they hand back to it; pass what the callback needs through that.
  A function value held in a variable does not convert either, since it may
  be a closure.
- **C types only.** C knows nothing of reference counts, so the parameter
  and return types must be numbers, `bool`, pointers, or other C function
  pointer types. A struct is an error:
  `C function pointer type 'extern (String) => int' cannot use 'String'; C passes only numbers, 'bool' and pointers`.
  Write pointers as `void*` in an `extern` declaration and as `__ptr<void>`
  elsewhere, as for any pointer.
- **A value like a number.** A C function pointer has no reference count.
  Store it in a variable, field or module-scope `const`, return it, pass it
  to other threads, or call it: `compare(a, b)` calls through it with the C
  calling convention. Calling a null one (from C) panics. It converts to
  `void*` but not to a Pepper function type; wrap it in a closure that calls
  it, `(x) => f(x)`, to use it as one.

`__function_pointer(name)` also gives a function's address, as an untyped
`__ptr<void>`. It takes a free function, or a static method of the struct
whose method uses it. Inside a generic struct the static method is the one
for the current type arguments, which is how `ThreadLocal<T>` gives the
operating system a destructor for its `T`. Prefer a C function pointer type
where the signature is known, since the compiler then checks it.

## Binding to a different symbol name

`[Link(name = "symbol")]` binds an extern to a C symbol whose name differs
from the declared one. Pepper code calls the extern by its declared name, and
the object file refers to `symbol`. Use it to give a C function a clearer
name, to avoid clashing with a Pepper name, or, together with
[`[Target]`](platform-selection.md), to bind one Pepper name to a different
symbol on each platform. `lib` names the library that defines the symbol in
the same attribute, as [`[Link("library")]`](linking.md#linking-a-library-from-the-source-link)
does on its own:

```pepper
{{#include ../../examples/c-link-name.pep}}
```

Real uses of the per-platform form include macOS on Intel, where the
64-bit-inode version of `stat` is named `stat$INODE64`:

```pepper
[Target(OS(Mac) && Arch(x64))]
[Link(name = "stat$INODE64")]
extern int stat(char* path, void* buf);
[Target(OS(Mac) && Arch(aarch64))]
extern int stat(char* path, void* buf);
```

`[Link]` takes the library as its one positional argument or as `lib`, and
the symbol as `name`; each is a non-empty string, and an extern names at
most one symbol. Anything else is an error, such as:

```text
main.pep:1:7: error: 'Link' has no argument named 'symbol'; use 'lib' or 'name'
    1 | [Link(symbol = "labs")] extern long pep_abs(long v);
      |       ^~~~~~
```

The earlier `[LinkName("symbol")]` was removed; it is an error that suggests
the `[Link(name = "symbol")]` that replaces it.

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
