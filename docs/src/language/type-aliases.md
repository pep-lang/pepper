# Type aliases

A type alias gives an existing type another name. Use one to shorten a long
type that you write often, such as `HashMap<String, Array<int>>`, or to say
what a value means, such as `Score` instead of `int`.

## Declaring an alias

Write `type`, the new name, `=`, and the type it stands for:

```pepper
{{#include ../../examples/type-aliases-basics.pep}}
```

An alias is only a spelling, not a new type. The compiler replaces every use
of the alias with its target before it checks anything else, so `Score` and
`int` are interchangeable: you can assign one to the other, pass one where the
other is expected, and error messages name the target type.

You can use an alias anywhere a type can appear: local and module-level
variables, parameters, return types, struct fields, generic arguments, and
casts. An alias of a struct also works where the struct's name would: to
construct it (`Team()`) and to call its static methods.

## Generic aliases

An alias can have type parameters of its own, including defaults, just like a
[generic struct](generics.md):

```pepper
{{#include ../../examples/type-aliases-generic.pep}}
```

The arguments at the use site fill the alias's parameters in order, and
omitted ones take their defaults. `Outcome<int>` becomes
`Result<int, Error>`, and `Lookup<int>` becomes `HashMap<String, int>`.
Aliases are especially handy for [function types](function-types.md), which
are long to write out: `Predicate<int>` reads better than `(int) => bool`.

## Aliases across files

Like other top-level declarations, an alias is private to the file (or
module) that declares it. Mark it `export` to let files that import it use it; see
[Visibility](visibility.md) and [Modules and imports](modules.md).

## Recursive aliases

An alias must not refer to itself, directly or through other aliases. The
compiler reports the cycle at the alias, with a note at each alias it passes
through:

```pepper
type Celsius = Degrees;
type Degrees = Celsius;
```

```text
main.pep:1:6: error: type alias 'Celsius' refers to itself
    1 | type Celsius = Degrees;
      |      ^~~~~~~
main.pep:2:6: note: through type alias 'Degrees', declared here
    2 | type Degrees = Celsius;
      |      ^~~~~~~
```
