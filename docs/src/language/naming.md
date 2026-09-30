# Naming conventions

Pepper code, including the standard library, follows one set of naming rules.
The compiler does not enforce them, but every example in this book, the
runtime, and the tools in this repository follow them, and code you
contribute should too.

| What | Style | Examples |
| --- | --- | --- |
| Structs, traits, type aliases | `PascalCase` | `String`, `HashMap`, `IoResult` |
| Generic parameters | one capital letter, or `PascalCase` | `T`, `K`, `V`, `TValue`, `TError` |
| Data members (fields) | `snake_case` | `unit_name`, `is_file` |
| Methods and free functions | `snake_case` | `append`, `remove_at`, `read_to_string` |
| Parameters and local variables | `snake_case` | `capacity`, `best_so_far` |
| Module-scope variables | `snake_case` | `max_requests` |
| Private data members and methods | `_` then `snake_case` | `_readings`, `_is_empty` |

```pepper
{{#include ../../examples/naming-basics.pep}}
```

## Types

A type name is `PascalCase`: each word starts with a capital letter, and there
are no underscores. Write an acronym as a word, so `IoError` and `HttpClient`,
not `IOError` or `HTTPClient`.

A generic parameter is either a single capital letter (`T`, `U`, `K`, `V`) or
a `PascalCase` name, which by convention starts with `T` (`TValue`,
`TError`). Use a single letter when the parameter's role is obvious, and a
name when a declaration has several parameters that a reader has to tell
apart.

## Members, functions, and variables

Everything else a program names is `snake_case`: lowercase words joined by
underscores. That covers a struct's data members, its methods, free
functions, parameters, local variables, and module-scope variables.

Spell words out. A name is read far more often than it is typed, so prefer
`iterate`, `index`, and `directory` to `iter`, `idx`, and `dir`. Keep an
abbreviation only when it is the usual name for the thing, such as `io` or
`c_str`.

An `extern` declaration keeps the name the C library gives the function,
whatever its style (`GetCurrentProcessId`), because that name is what the
linker looks up. The same goes for the fields of a struct that mirrors a C
struct.

## Private members

Pepper has no member-level `private` keyword; any code that can reach an
object can name all of its members. A leading `_` marks a data member or
method as private to its struct instead: code outside the struct, and its
extensions, should not use it. The rest of the name is `snake_case`, as for a
public member (`_readings`, `_is_empty`).

The standard library relies on this convention: its generated reference
leaves `_` members out, and [doc comments](doc-comments.md) are required only
on members without the prefix.

A top-level declaration does not need the prefix to be private: it is
private to its file unless it is exported (see [Visibility](visibility.md)).
The runtime also uses the prefix on top-level helpers that its own files
export to each other, such as `_pep_malloc`: they are not part of its public
API, and the reference leaves them out too.
