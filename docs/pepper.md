# Pepper

## Core Types

* `i8`, `u8`, `char`, `byte` - 8-bit signed/unsigned characters/integers
* `i32`, `u32`, `int`, `uint` - 32-bit signed/unsigned integers
* `i64`, `u32`, `long`, `ulong` - 64-bit signed/unsigned integers
* `float`, `double` - 32 and 64-bit IEEE floating point numbers
* `void` - The absence of a type, mostly used for non-value returning functions

### Built-in Types

* `string` - A UTF-8 encoded string of code points
* `array<T>` - A dynamic array of `T`s.

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
# parentheses are optional
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
array<uint> fibonacci_sequence(uint count) {
    array<uint> nums(count);
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
a constructor (`construct`) and a destructor(`destruct`). Within a structure's code, the current instance is referred to
as `this`.

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

## Traits

### Extensions

## Accessing C Functions

Calling C functions from Pepper just requires that the function is declared using `@extern`, and that a library
containing the function is linked (using the `-l` flag to `pepper` when building or by adding a library to the
`[link]` section in `pepper.toml`):

```
@extern char getchar();
@extern void printf(char* fmt, ...);
```

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