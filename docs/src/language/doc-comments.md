# Documentation comments

Comments explain code to the people who read it. Pepper has one comment
syntax, `#`, and a convention on top of it for documentation: lines starting
with `##` directly above a declaration document that declaration. Your editor
shows them when you hover over a use of the name, and the
[standard library reference](../reference/README.md) in this book is generated
from them.

## Comments

A comment starts with `#` and runs to the end of the line. It can take a whole
line or follow code:

```pepper
# Count the lines that are not blank.
var count = 0;   # blank lines are skipped below
```

Pepper has no block comment syntax: to comment out several lines, start each
with `#`. (`//` is not a comment in Pepper.)

## Doc comments

A doc comment is a run of consecutive lines that start with `##`, directly
above the declaration it documents:

```pepper
## Returns the larger of `a` and `b`.
##
## @param a the first value
## @param b the second value
## @returns `a` when it is at least `b`, otherwise `b`
larger(a: int, b: int): int {
    return a >= b ? a : b;
}
```

- The text of each line is what follows `## `. A line that is just `##` is a
  blank line in the documentation, which separates paragraphs.
- The comment must sit directly above the declaration, with no blank line in
  between. [Attributes](platform-selection.md) and `export` or `static` may
  come between the comment and the declaration, so put the comment above the
  attributes.
- Only lines that start with exactly two `#` count. A single `#` is an
  ordinary comment, and a line starting with three or more, such as a
  decorative `#######`, is not documentation.
- A doc comment works on functions, structs, traits, extensions, type aliases,
  module-scope variables, and the fields, constructors and methods inside a
  struct, trait or extension.

## What to write

Start with a **description**: what the declaration does, in the third person
("Returns ...", "Appends ..."), followed by what a caller needs to know, such
as edge cases, who owns what, how long it takes, and differences between
platforms. The description is Markdown, so put code in backticks.

After the description come **tags**, each starting a line with `@`. A tag's
text runs until the next tag.

| Tag | Use it for |
|---|---|
| `@typeParam T description` | each generic parameter of a generic struct, trait, type alias or function |
| `@param name description` | each parameter of a function, method or constructor |
| `@returns description` | what the function returns, whenever it returns a value |
| `@panics description` | each way a caller can make the function panic (a failed `assert`, a call to `panic`) |
| `@example` | sample code, indented on the lines that follow; line breaks are kept |
| `@see name` | a related declaration |
| `@note text` | a remark that does not fit elsewhere |

Write tag descriptions like clang writes errors: lowercase start, no trailing
period. A field or a type alias usually needs only one line:
`## The number of bytes in the buffer.`

Keep notes that matter only to the people maintaining the code in ordinary `#`
comments inside the body. The doc comment is the contract with callers.

Here is a small documented library:

```pepper
{{#include ../../examples/doc-comments-basics.pep}}
```

## Where doc comments appear

- **In your editor.** The Pepper language server shows a declaration's doc
  comment when you hover over its name, anywhere it is used. The description
  comes first, followed by sections for the type parameters, parameters,
  return value, panics, related declarations, notes and examples.
- **In the standard library reference.** The
  [reference pages](../reference/README.md) are generated from the doc comments
  in the runtime, one page per runtime file. A `##` block at the very top of a
  file, followed by a blank line, introduces that file's page.
  [Building this documentation](../contributing/docs.md) explains how to
  regenerate them.

## The standard library is fully documented

Every public declaration in the runtime must have a doc comment: every
exported declaration whose name does not start with `_`, and every field,
constructor and method of such a struct, trait or extension whose name does
not start with `_`. Names starting with `_` are internals shared between
runtime files and are exempt.

A test enforces this, and reports a clang-style error for each gap: a missing
doc comment, a comment with no description, a missing `@param`, `@typeParam`
or `@returns`, a tag with no description, a `@returns` on a function that
returns nothing, or a `@param` naming a parameter that does not exist. If you
contribute to the runtime, run the test suite before you send a change. The
compiler does not check the doc comments in your own programs, but following
the same format gets you the same editor support.
