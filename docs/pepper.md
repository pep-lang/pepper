# Pepper

## Core Types

* `i8`, `u8`, `char`, `byte` - 8-bit signed/unsigned characters/integers
* `i16`, `u16`, `short`, `ushort` - 16-bit signed/unsigned integers
* `i32`, `u32`, `int`, `uint` - 32-bit signed/unsigned integers
* `i64`, `u64`, `long`, `ulong` - 64-bit signed/unsigned integers
* `float`, `double` - 32 and 64-bit IEEE floating point numbers
* `void` - The absence of a type, mostly used for non-value returning functions

### Built-in Types

* `String` - A UTF-8 encoded string of code points
* `Array<T>` - A dynamic array of `T`s.
* `Result<TValue, TError=Error>` - A success-or-failure value (Rust `Result`-analogous); see [Results](#results).
* `Error` - The default error type for `Result`: a struct holding a `String Message`.
* `None` - An empty struct, the value type of a `Result` with nothing to return on success: `Result<None>`.

### Naming conventions

Primitives and keywords are lowercase (`int`, `float`, `bool`, `var`, ...).
Runtime/prelude structs are PascalCase: `String`, `Array<T>`, `HashMap<K, V>`,
`HashSet<K>`, `Atomic<T>`, `Result<TValue, TError>`. New runtime structs MUST use PascalCase. `int[]` is
sugar for `Array<int>` (nested brackets nest: `int[][]` is `Array<Array<int>>`).

## Variables

Variables can be declared with explicit or implicit types. Implicit types are preferred in any case where the type
can be divined from surrounding code (usually via assignment).

### Explicitly Typed

```
int x = 42;
float y = 42.0;
```

### Implicitly Typed

```
var x = 42; # will produce an int by default
var y = 42.0; # will produce a float by default
```

### Casting

Casting in Pepper uses the `as` keyword. This is the equivalent of a `static_cast` from C++, or an `as` cast in C#.
If the cast cannot succeed, a compile error will be generated.

```
float x = 0;
int y = x as int;
```

## Control Flow

### Branches

```
var x = 1;
# parentheses are optional, braces are not
if x > 0 {
    print("Greater than 0");
}
```

### Loops

```
var nums = Array<int>();
nums.append(0);
nums.append(2);
nums.append(4);

for (var x in nums) {
    print(x, "\n");
}

var idx = 0;
while (idx < nums.count()) {
    print(nums[idx], "\n");
    idx = idx + 1;
}
```

`break` and `continue` work in both. As with `if` and `while`, the parentheses around a `for` header are optional
(`for var x in nums { ... }`), and the loop variable may be typed (`for (int x in nums)`, `for (var x: int in nums)`).

#### Iteration

A `for` loop works with any type that follows the iterator protocol (`runtime/iterator.pep`):

```
export trait Iterator<T> {
    bool next();     # advance; true if there is a current element
    T current();     # the element next() just moved to
}

export trait Iterable<T> {
    iterate(): Iterator<T>;
}
```

`for (var x in source) { body }` behaves exactly like:

```
{
    var it = source.iterate();   # or `var it = source;` when source is itself an Iterator
    while (it.next()) {
        var x = it.current();
        { body }
    }
}
```

The loop picks the form by the methods the source's type has, like C++ range-for: `iterate()` first, else `next()` and
`current()`. A type with neither is a compile error:
`type Foo is not iterable: implement Iterable<T> (iterate()) or Iterator<T> (next() and current())`. Traits are not
checked yet, so declaring one (`extend Foo with Iterator<int> {}`) documents intent rather than being required.

- The loop variable is a copy, like any `var`: rebinding it does not write back to the collection. For struct elements
  it is another reference to the same object, so `x.Field = ...` does change the element.
- The iterator holds a reference to its source, so iterating a temporary (`for (var x in make_list())`) keeps it alive
  for the whole loop. Leaving the loop by `break` or `return` releases the iterator; a destructor on it runs then.
- When the source is itself an iterator stored in a variable, the loop shares that object: it is exhausted afterwards.
- `current()` before the first `next()`, or after `next()` returned false, panics.

Built-in iterables:

| Type | Yields |
|---|---|
| `Array<T>` | each element, in order (`ArrayIterator<T>`) |
| `String` | each code point, as a one-code-point `String` (the same value as `s[i]`; `StringIterator`) |

Modifying an `Array` or `String` while a loop iterates it panics (`Array modified during iteration`). Every mutating
`Array` method counts, element stores (`arr[i] = v`) included; for `String`, `append` and `grow`. Modifying it after the
loop is fine.

## Functions

Functions in Pepper can be defined as free functions (in file/module scope) or as struct methods.

```
Array<uint> fibonacci_sequence(uint count) {
    Array<uint> nums(count);
    uint num = 1;
    nums.append(1);
    for (1...count) {
        if nums.size() > 0 {
            num += nums[nums.size() - 1]
        } 
        nums.append(num);
    }
    return nums;
}
```

## Structures

Pepper's object model is built around structures and traits. There is no inheritance in Pepper, rather structures have
functionality added to them by implementing traits. Traits can be added to structs anywhere, so even a library type
can be extended by user code.

Structures are declared with `struct`, similarly to many other languages:

```
struct Point {
    int x = 0;
    int y = 0;
}
```

Structures can have methods attached to them in their declaration blocks, or via extension elsewhere. Structures have
a constructor (`construct`, also accepted as `new`) and a destructor (`destruct`). Within a structure's code, the current
instance is referred to as `this`.

```
struct Point {
    int x = 0;
    int y = 0;
    
    # Assignment to fields can be shorthanded to `this.<field>` as an argument to a constructor
    construct(this.x = 0, this.y = 0) {
    
    }
    
    # The above constructor could equally be written as
    construct(int x = 0, int y = 0) {
        this.x = x;
        this.y = y;
    }
}
```

## Generics

Pepper's generics should be straightforward relative to other languages. Making a type or function generic is as simple
as adding type parameters:

```
struct MyContainer<T> {
    void insert(T element) {
        # ...
    }

    void insert<U>(U element) {
        insert(U as T);
    }
    # ...
}

void print_container<C>(C container) {
    # ...
}
```

Generic parameters may carry a default type, used when a use omits that argument: `struct Result<TValue, TError=Error>` lets both `Result<int>` and `Result<int, MyErr>` name the same base. Defaults are filled in at specialization; the specialized instance keeps the name as written (`Result<int>` is its own specialization, distinct from `Result<int, Error>`).

## Type aliases

A `type` declaration names an existing type, optionally with its own generic parameters:

```
type I = int;
type Pair = Result<int, Error>;
type R<T, E=Error> = Result<T, E>;
```

Aliases are expanded at every use site before any other pass runs, so downstream code and the compiler see only the target type — an alias is a spelling, not a new type. Generic aliases fill their parameters positionally from the arguments given at the use site; omitted arguments fall back to parameter defaults (`R<u32>` is `Result<u32, Error>`, exactly as with generic structs). An alias may be used in any type position: locals, globals, function signatures, struct fields, casts. Aliases work across files — a module may define an `export`ed alias and other modules that import it may use it (see [Visibility](#visibility)).

An alias must not reference itself, directly or through a chain of aliases; the compiler aborts with an error naming the cycle.

## Visibility

Every top-level declaration — functions (including `extern` declarations), structs, type aliases, traits,
extensions, and module-scope variables — is private to the file that declares it. Prefix the declaration with
`export` to make it usable from other files that import it (see [Modules and imports](#modules-and-imports)):

```
# lib.pep
export struct Point {
    var x: int;
    var y: int;
}
export type Points = Point[];
export trait Printable { print(); }
export var origin_count = 0;
export origin(): Point { return make(0, 0); }
make(x: int, y: int): Point { ... }     # private: only lib.pep can call it

export extend Point with Printable {
    print() { ... }
}
extend Point {
    norm(): int { ... }                 # private extension: only lib.pep can call p.norm()
}

# main.pep
import "lib";
main(): int {
    var p = origin();   # ok
    p.print();          # ok: exported extension
    var q = make(1, 2); # error: 'make' is private to lib.pep
    var n = p.norm();   # error: 'norm' is declared in a private extension in lib.pep
    return p.x;
}
```

`export` goes directly before the declaration's keyword or name, after any attributes:
`[Target(OS(Windows))] export f()`. Writing it before the attributes (`export [Target(OS(Windows))] f()`) is a
parse error.

Fields and methods declared in a struct's body are reached through the struct, so they share its visibility.
Methods added by an extension share the extension's visibility instead: a private extension's methods can be
called only from the file that declares it, even on an exported struct, and a trait it implements is only
available through it in that file. Visibility is checked before types are known, so members are matched by
name: a call `x.m()` from another file is accepted if any struct body or extension visible to the calling file
(its own, or exported) declares an `m`. Extending a struct does not make a private struct visible. The runtime's
public surface (`String`, `Array`, `HashMap`, `HashSet`, `Atomic`, `Result`, `Error`, `hash`, `assert`, `panic`,
…) is exported this way, and is visible to every file without an import.

All files of a program still share one namespace, so a private name must not also be declared in another file;
the compiler reports `private 'helper' is also declared in b.pep`. `extern` declarations are exempt, since every
declaration of an extern names the same C function; so is a concrete override such as `hash<int>` of an
exported generic `hash<T>`, and so are declarations that a `[Target(...)]` attribute drops for the current
platform. Overriding one the runtime already provides, such as `hash<String>`, is a duplicate.
Concrete overrides are only supported for primitive types and `String`: `hash<Point>` declares a second generic
function with a type parameter named `Point`, which collides with `hash<T>`. Type parameters are compared by
position, not name, so a private `pick<U>` also collides with `pick<T>`.

`export` controls visibility between Pepper files only; C linkage is the separate `[Export]` attribute described
in [Exporting functions](#exporting-functions).

## Modules and imports

A module is a folder that contains a `module.pep` file. The module is named after the folder, and its exports
are exactly what its `module.pep` exports.

```
deps/
    geometry/
        module.pep  # the module's exports
        shapes.pep  # a file of the module, imported by module.pep
main.pep
```

An import names its source in one of two ways:

- `import geometry`, an identifier, is a dependency: a module found on the search paths, which are the `-I`
  directories, then the runtime directory. The program above compiles with `pepper main.pep -I deps`.
- `import "shapes"`, a string, is local, relative to the importing file: the file `shapes.pep`, which must belong
  to the importing file's module (for a file outside any module, lie in its folder or below, outside any module
  nested there), or else the module folder `shapes/`, such as a module nested in this one or one next to the
  program. `import "../other/x"` naming a file of another module is an error; import that module's folder
  instead.

Imports come in these forms, and every import comes before all of a file's declarations and re-exports:

- `import geometry` makes the module's exports available qualified by its name: `geometry.Point`,
  `geometry.area(2, 3)`.
- `import geometry as g` or `import "geometry" as g` does the same under the name `g`: `g.Point`, `g.area(2, 3)`.
- `import [area, Point as Pt] from geometry` (or `from "util"`) makes the named exports available unqualified,
  `area` under its own name and `Point` as `Pt`.
- `import "shapes"` makes the exports of `shapes.pep` (or of the module folder `shapes/`) available unqualified.

Qualified names work wherever a name does: in expressions (`g.area(1, 2)`, `g.origin_count`), in types
(`var p: g.Point`, `g.Box<int>[]`, `g.Point origin()`), and in generic constructions (`g.Box<int>()`). A generic
construction is recognized only for a qualifier imported earlier in the file; elsewhere `a.b < c, d > (e)` is two
comparisons. A qualifier or an imported name
is shadowed by a local, parameter, generic parameter, or struct member of the same name, but a file may not
import a name it also declares at top level. A name listed in `import [...]` wins over the same name from a
whole-file import; two whole-file imports that provide a name differently make it ambiguous where it is used.
Because an imported name is compiled as the name of the declaration it denotes, a local with that
declaration's name may not be in scope where it is used: if `geometry.rect_area` is `shapes.pep`'s `area`,
then `g.rect_area(1, 2)` inside a function with a parameter named `area` is an error asking you to rename one. The exports of a file or module a file did not import are not
visible to it, even when another file of the program imports them:

```
# main.pep
import geometry;
main(): int { return area(1, 2); }  # error: 'area' is exported by geometry/shapes.pep, which this file does not import
```

`export symbol as name;` exports `symbol` to importers as `name`; `export symbol;` exports it under its own name
(the `;` is required: without it, `export P` followed by a declaration is an exported C-style declaration).
The symbol may be declared in the file, even privately, or imported from another file or module, qualified or not.
This is how a `module.pep` publishes what its other files define:

```
# geometry/shapes.pep
export area(w: int, h: int): int { return w * h; }
export struct Box<T> { var value: T; }

# geometry/module.pep
import "shapes";
export struct Point { var x: int; var y: int; }
helper(): int { return 0; }
export area as rect_area;   # geometry.rect_area is shapes.area
export Box;                 # geometry.Box is shapes.Box
export helper as reset;     # a private declaration, exported under another name
```

`shapes.pep`'s own exports are not the module's: an importer of `geometry` can use `geometry.rect_area` and
`geometry.Box`, but `geometry.area` is an error.

An import or re-export may carry attributes like any declaration: `[Target(OS(Linux))] import linux;` and
`[Target(OS(Linux))] export linux_open as open;` are ignored on other platforms. A module imports a module nested
in its own folder by path: `geometry/module.pep` may `import "shapes3d" as s3` for `geometry/shapes3d/module.pep`.

The runtime is not a module: its files are loaded into every program, and their exports are visible everywhere
without an import. `--import NAME` adds a module (or a `NAME.pep` file) found on the search paths to that prelude; a name that
resolves to neither is an error.

Imports bind names; they do not create separate namespaces. All files of a program still share one namespace for
their declarations, so an exported name must not be declared by any other file either, even in another module
reached through its own qualifier: `exported 'f' is also declared in b/module.pep`. Prelude files, meaning the
runtime and any `--import` modules (with their other files), are exempt by design and may repeat each other's
exports, so a forced import can supply its own definition of a runtime export such as `panic`: it is loaded ahead
of the runtime and its definition wins. It must declare the name itself (`export panic(...)`); re-exporting
another function under a runtime export's name is an error, since the runtime's own files would keep calling theirs.

## Traits

## Extensions

## Accessing C Functions

Calling C functions from Pepper just requires that the function is declared using `extern`, and that a library
containing the function is linked (using the `-l` flag to `pepper` when building, by adding a library to the
`[link]` section in `pepper.toml`, or by attaching `[Link("name")]` to the extern itself):

```
extern char getchar();
extern void printf(char* fmt, ...);

[Target(OS(Windows))] [Link("gdi32")] extern ulong GetStockObject(int objid);
```

A C function with a variable argument list ends its parameters with `...`, after at least one named parameter:
`extern int snprintf(char* buf, ulong n, char* fmt, ...);`. The call uses the C calling convention for variadic
functions (which differs from a plain call on some targets, such as Apple arm64), and each argument past the named
ones gets C's default argument promotions: integers narrower than `int` widen to `int`, `float` to `double`.

A string literal passed to an extern is a NUL-terminated C string: `strlen("hello")` is 5. A `String` value is
passed with `s.c_str()`.

A `[Link("name")]` attribute on an extern that survives platform filtering adds `-l{name}` to the link step;
duplicates are linked once.

`[LinkName("symbol")]` binds an extern to a C symbol whose name differs from the declared one. Pepper code calls
the extern by its declared name; the object file references `symbol`. Combined with `[Target(...)]`, one Pepper
name can bind to a different symbol per platform:

```
[LinkName("llabs")] extern long abs64(long v);

[Target(OS(Mac) && Arch(x64))] [LinkName("stat$INODE64")] extern int stat(char* path, void* buf);
[Target(OS(Mac) && Arch(aarch64))] extern int stat(char* path, void* buf);
```

`LinkName` takes exactly one non-empty string, and an extern may carry at most one.

### Pointers

Pepper spells a raw pointer `__ptr<T>`: `__ptr<void>`, `__ptr<char>`, `__ptr<__ptr<int>>`. A pointer supports
`p + n` (strides by `sizeof<T>`, bytes for `__ptr<void>`), indexing `p[i]`, comparison with `__null`, casts to an
integer (`p as ulong`) or to another pointer type (`p as __ptr<char>`), and passing to externs that take `T*`.

C-style `T*` (`void*`, `char*`, `int**`) is accepted **only** in `extern` declarations, whose parameter and return
types mirror the C prototype. Anywhere else — function parameters and returns, struct fields, locals, globals,
type alias targets, generic arguments, casts — `T*` is a parse error:

```
extern void* memset(void* p, int c, ulong n);   # ok: extern prototype

clear(p: __ptr<void>, n: ulong) {               # ok
    memset(p, 0, n);
}

clear(p: void*, n: ulong) { ... }
# error: C pointer syntax `void*` is only allowed in extern declarations; use `__ptr<void>`
```

## Exporting functions

The `[Export]` attribute attached to any global function will create a C linkage exported function. Types used
in the function signature are automatically lowered to C types, with object references becoming opaque handles
(effectively `void*` from C's perspective).

## Platform selection

The `[Target(...)]` attribute selects code for the compile target, which is always the host
platform. It takes exactly one argument: a boolean expression built from `OS(...)` and `Arch(...)`
calls. It can be attached to top-level functions, externs, structs, traits, extensions, type aliases,
module-scope variables, struct/trait/extension methods, and to blocks inside function bodies:

```
[Target(OS(Windows))] type FileHandle = __ptr<void>;
[Target(!OS(Windows))] type FileHandle = int;

[Target(OS(Windows))]
int window_width() { return 80; }

[Target(!OS(Windows))]
int window_width() { return 120; }

main(): int {
    [Target(OS(Windows) || OS(Mac))] {
        // Windows- and Mac-only code.
    }
    [Target(Arch(aarch64))] {
        // ARM-specific code.
    }
    return window_width();
}
```

- `OS` accepts `Windows`, `Mac`, and `Linux`; `Arch` accepts `x64` and `aarch64`. Values are matched
  case-insensitively.
- The argument combines with `&&`, `||` (or `and`/`or`) and negates with `!`, e.g.
  `[Target(OS(Linux) && Arch(x64))]` or `[Target(!(OS(Windows) || OS(Mac)))]`.
- Multiple attributes on one item are ANDed: the item is kept only if all of them match.
- A block whose attribute does not match the host is removed entirely before compilation, so code that
  references platform-specific symbols (such as `extern` declarations) is fine as long as it is dropped on
  the current host.
- `OS(...)` and `Arch(...)` are only valid inside `Target(...)`; a top-level use, or any boolean logic
  directly in the brackets (`[Target(OS(Windows)) && Export]`), is a parse error.
- Platform predicates on struct fields are a parse error; platform selection applies to whole declarations,
  not individual fields.

## Linking
### Default System Libraries/Linking

By default, executables will link the following libraries when built by `pepper`:

#### Windows

* msvcrt.lib
* ucrt.lib
* vcruntime.lib
* kernel32.lib
* user32.lib
* shell32.lib

#### POSIX

* libc.so will be required, but not linked

#### OSX

* `ld` will be invoked with `-platform_version [macos|ios] "12.1.0", "12.3"`
  and `-syslibroot /Library/Developer/CommandLineTools/SDKs/MacOSX12.sdk`

## Atomics

`Atomic<T>` (in the runtime prelude) is a `std::atomic<T>`-equivalent wrapper. The slot holds the value in place for POD `T`, and the reference itself for struct `T`; every operation lowers to a native LLVM atomic instruction:

```
var c = Atomic<int>(0);
c.store(1);              # release store
c.load();                # acquire load
c.fetch_add(5);          # returns the previous value (integer T)
c.compare_exchange(1, 2);# true iff the slot was 1 and is now 2
c.exchange(3);           # CAS loop; returns the previous value
c.is_lock_free();        # true for POD T of <= 8 bytes and struct T
```

`fetch_sub`, `fetch_and`, `fetch_or`, and `fetch_xor` are provided alongside `fetch_add`. For struct `T`, `store`/`compare_exchange` swap the slot's reference atomically, so the usual shared-reference rules apply to the old and new values.

## Results

`Result<TValue, TError>` (in the runtime prelude) is a Rust-`Result`-analogous success-or-failure value. `TError` defaults to `Error`, so `Result<int>` and `Result<int, Error>` are equivalent in use — values interoperate freely, though each spelling produces its own specialization. Pepper has no unions: both `Value` and `Error` always exist, and `IsOk` selects the live one (the dead field stays at its default/null value).

```
var ok = Result<int>.ok(42);        # IsOk = true, Value = 42
var err = Result<int>.err(Error("boom"));
ok.is_ok();                          # true
err.is_err();                        # true
ok.unwrap();                         # 42; panics on an Err
err.ok_or(-1);                       # -1 (fallback when IsOk is false)
```

`Error` is a struct with a single `String Message` field: `var e = Error("boom"); e.Message`.

An operation with nothing to return on success uses `None`, an empty struct, as its value type (Rust's
`Result<(), E>`):

```
var done = Result<None>.ok(None());
var failed = Result<None>.err(Error("disk full"));
```

## The io module

`runtime/io/` is a module, not part of the prelude: `import io` (then `io.File`, `io.Path`, ...) or
`import [File, Path, Directory] from io`. It is modeled on Rust's `std::fs` and `std::path`.

```
import [File, OpenOptions, Directory, Path] from io;

main(): int {
    var dir = Directory.temp().join_str("demo");
    Directory.create_all(dir);
    var notes = dir.join_str("notes.txt");
    File.write_text(notes, "hello");
    var more = OpenOptions().append(true).open(notes).unwrap();
    more.write_string(", world");
    more.close();
    var text = File.read_to_string(notes);
    if (text.is_err()) {
        print(text.Error.Message);
        return 1;
    }
    Directory.remove_all(dir);
    return 0;
}
```

- **Results.** Fallible operations return `IoResult<T>` (`Result<T, IoError>`); those with nothing to return use
  `IoResult<None>`. `IoError` holds the raw platform `Code` (errno / `GetLastError()`) and a `Message`, and
  classifies it with predicates: `is_not_found()`, `is_permission_denied()`, `is_already_exists()`,
  `is_not_a_directory()`, `is_is_a_directory()`, `is_directory_not_empty()`, `is_invalid_input()`,
  `is_interrupted()`.
- **`Path`** wraps a `String Value`. Pure operations: `join(Path)` and `join_str(String)` (an absolute right-hand
  side replaces the left), `parent()`, `file_name()`, `file_stem()`, `extension()`, `with_extension(ext)`,
  `components()`, `normalize()` (lexical: drops `.`, resolves `..`, collapses separators; `"a/.."` is `"."`),
  `is_absolute()`, `is_relative()`, `is_empty()`, `Path.separator()`, `==`. "No value" is an empty `Path` or
  `String`: `Path("/").parent()` and `Path("a/..").file_name()` are empty. File-system queries: `exists()`,
  `is_file()`, `is_dir()`, `metadata()` (follows symlinks), `symlink_metadata()`, `canonicalize()`.
- **`File`** owns a handle and closes it when the last reference goes; `close()` closes early and reports the
  error (it is idempotent). `File.open(p)` reads, `File.create(p)` writes (creating or truncating), and
  `File.open_with(p, options)` or `OpenOptions().read(..).write(..).append(..).truncate(..).create(..)
  .create_new(..).open(p)` choose. Instance I/O: `read(buf, max)` appends up to `max` bytes to a `u8[]`
  (0 at end of file), `read_all()`, `read_string()` (rejects invalid UTF-8), `write(bytes)` (may be partial),
  `write_all(bytes)`, `write_string(s)`, `seek_start/seek_end/seek_current(offset)`, `set_len(n)`, `sync()`,
  `metadata()`. Whole-file helpers are static: `read_bytes`, `read_to_string`, `write_bytes`, `write_text`,
  `copy`, `rename`, `remove`. `File.stdin()`, `stdout()`, `stderr()` are never closed by `File`.
- **`Directory`**: `open(p)` (checks it is a directory), `entries()` (every `DirEntry` except `.` and `..`,
  eagerly, with `Name`, the joined `Path`, `IsFile`/`IsDir`/`IsSymlink`), static `create`, `create_all`,
  `remove` (must be empty), `remove_all` (removes symlinks, never follows them), `current`, `set_current`,
  `temp`.
- **`Metadata`**: `Size`, `IsFile`, `IsDir`, `IsSymlink`, `ReadOnly`, `Modified`/`Accessed`/`Created` (ns since
  the Unix epoch; `Created` is 0 where the file system has no birth time) and `Permissions` (POSIX mode bits,
  or `FILE_ATTRIBUTE_*` bits on Windows).
- **Platform types**: `FileHandle` (a descriptor `int`, or a `HANDLE` `__ptr<void>` on Windows), `ErrorCode`,
  `Mode`, and `Offset` (`long` everywhere).

The public types are written against a private platform layer, `_io_sys_*` functions declared twice with identical
signatures: `sys_posix.pep` (`[Target(!OS(Windows))]`, with Linux/macOS differences selected by `OS(...)` and
`Arch(...)`) and `sys_windows.pep` (`[Target(OS(Windows))]`, the UTF-16 `*W` APIs in kernel32). All files of a
program share one namespace, so the module's C functions (`open`, `read`, `write`, `close`, `stat`, `rename`,
...) take those names program-wide, and its private helpers are prefixed `_io_`.
