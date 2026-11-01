# Attributes

An attribute is a name in square brackets that tells the compiler something
about the declaration below it. Each attribute goes on its own line, above
its target, as `pep-fmt` writes it, except a parameter's, which stay on its
line, in front of it:

```pepper
{{#include ../../examples/attributes.pep}}
```

The built-in attributes are each covered in the chapter for what they do:

| Attribute | Goes on | Chapter |
|---|---|---|
| `[Value]` | a struct or enum | [Value structs](value-structs.md), [value enums](enums.md#value-enums) |
| `[Equatable]` | a struct or enum | [Deriving `==` and `hash`](hashing.md#deriving-both-with-equatable) |
| `[Implicit]` | a constructor | [Implicit conversions](structs.md#implicit-conversions) |
| `[Alias]`, `[Rename]` | a parameter | [Other names for a parameter](functions.md#other-names-for-a-parameter) |
| `[Shared]` | a struct | [What threads can share](threads.md#what-threads-can-share) |
| `[ThreadLocal]` | a module-scope `var` | [Thread-local variables](threads.md#thread-local-variables) |
| `[Isolated]` | a struct | [What a lock body may do](threads.md#what-a-lock-body-may-do) |
| `[Move]`, `[MoveSource]` | a parameter | [Handing a reference over with move](memory.md#handing-a-reference-over-with-move) |
| `[NotCopyable]`, `[Locked]` | a struct; a parameter | the [reference](../reference/attributes.md) |
| `[Unsafe]` | a function | [Removing the checks](types-and-variables.md#removing-the-checks) |
| `[Likely]`, `[Unlikely]` | an `if` or a `match` arm | [Branch hints](control-flow.md#branch-hints-likely-and-unlikely) |
| `[Cold]` | a function | [Cold functions](hints.md#cold-functions) |
| `[Target]` | most declarations, and blocks | [Platform selection](platform-selection.md) |
| `[BuildOption]` | a declaration or a block | [Build options](build-options.md) |
| `[Link]` | an `extern` function | [Linking](linking.md) |
| `[Export]` | a function | [Calling Pepper from C](c-interop.md#calling-pepper-from-c) |
| `[Test]`, `[ShouldPanic]` | a function | [Unit tests](testing.md) |
| `[Deprecated]` | most declarations | [Deprecation](deprecation.md) |
| `[Attribute]` | a struct | [Attributes of your own](reflection.md#attributes) |
| `[Name]`, `[Ignore]`, `[Required]`, `[Tag]`, `[Untagged]` | a property; an enum or its cases | [JSON: attributes](json.md#attributes) (the `serialize` module) |
| `[cli.Option]`, `[cli.Positional]` | a field | [Declaring options as a struct](cli.md#declaring-options-as-a-struct) |

A struct marked `[Attribute]` is an attribute of your own, which a `static`
block reads at compile time (see
[Reflection and attributes](reflection.md#attributes)). The built-in ones are
declared the same way, in the runtime, so the
[reference](../reference/attributes.md) lists each with its fields.
