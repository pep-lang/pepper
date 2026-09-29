# Pepper

## Core Types

* `i8`, `u8`, `char`, `byte` - 8-bit signed/unsigned characters/integers
* `i32`, `u32`, `int`, `uint` - 32-bit signed/unsigned integers
* `i64`, `u32`, `long`, `ulong` - 64-bit signed/unsigned integers
* `float`, `double` - 32 and 64-bit IEEE floating point numbers
* `void` - The absence of a type, mostly used for non-value returning functions

### Built-in Types

* `String` - A UTF-8 encoded string of code points
* `Array<T>` - A dynamic array of `T`s.
* `Result<TValue, TError=Error>` - A success-or-failure value (Rust `Result`-analogous); see [Results](#results).
* `Error` - The default error type for `Result`: a struct holding a `String Message`.

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
for (var x in [0, 2, 4]) {
    print(x, "\n");
}

var nums = [0, 2, 4];
var idx = 0;
while (idx < nums.size()) {
    print(nums[idx++], "\n");
}
```

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
`export` to make it usable from other files:

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
use "lib";
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
…) is exported this way.

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

## Exporting functions

The `[Export]` attribute attached to any global function will create a C linkage exported function. Types used
in the function signature are automatically lowered to C types, with object references becoming opaque handles
(effectively `void*` from C's perspective).

## Platform selection

The `[Target(...)]` attribute selects code for the compile target, which is always the host
platform. It takes exactly one argument: a boolean expression built from `OS(...)` and `Arch(...)`
calls. It can be attached to top-level functions, externs, structs, traits, extensions, struct/trait/
extension methods, and to blocks inside function bodies:

```
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
