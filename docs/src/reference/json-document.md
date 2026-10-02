<!-- Generated from runtime/json/document.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Documents with comments

`JsonDocument`: a JSONC document that keeps its comments, so a settings
file can be read, changed and written back with them.

Source: `runtime/json/document.pep`

## JsonDocument

```pepper
struct JsonDocument
```

A JSON value with the comments of the JSONC text it was read from, as
`parse_document` makes it.

Each comment belongs to a value, by the value's path from the root `$`
(`$.editor.tab_size`, `$.files[0]`): the comments on the lines before
a value, or on the line it ends (after its comma), stay with it, and
those before a closing bracket stay at the end of their array or object.
`to_string()` writes them back in those places, so text read and
written unchanged keeps every comment, in the indented layout
`to_pretty_string` uses.

Change `root` freely. A comment whose value is gone (a removed key, an
array shortened past it) is not written; one whose path names another
value afterwards (an element shifted into its index) goes with that
value.

**Example**
```pepper
    import json;

    var text = "{\n  // The editor.\n  \"tab_size\": 4, // spaces\n  \"wrap\": true\n}";
    var document = json.parse_document(text).value();
    document.root["wrap"] = json.JsonValue.Bool(false);
    assert(
        document.to_string() == "{\n  // The editor.\n  \"tab_size\": 4, // spaces\n  \"wrap\": false\n}",
        "the comments stay"
    );
    assert(document.comments("$.tab_size")[0] == "// The editor.", "by path");
```

### Fields

#### root

```pepper
var root: JsonValue
```

The document's value.

### Constructor

#### JsonDocument()

```pepper
construct(root: JsonValue = JsonValue.Null)
```

Creates a document holding `root`, with no comments.

**Parameters**
- `root` — the document's value

### Methods

#### comments

```pepper
comments(path: String): Array<String>
```

Returns the comments on the lines before the value at `path`, each
with its `//` or `/* */`.

**Parameters**
- `path` — the value's path from the root: `$`, `$.key`, `$[0]`, or `$["a key"]` for a key that is not an identifier

**Returns**
- the comments, oldest first; empty when there are none

#### set_comments

```pepper
set_comments(path: String, comments: Array<String>)
```

Replaces the comments on the lines before the value at `path`. Each
must be a whole comment, `// ...` (one line) or `/* ... */`.

**Parameters**
- `path` — the value's path from the root, as for `comments`
- `comments` — the comments to write before the value; empty removes them

**Panics**
- if a comment does not start with `//` or `/*` ("a JSONC comment starts with '//' or '/*'")

#### to_string

```pepper
to_string(indent: int = 2, ascii_only: bool = false): String
```

Returns the document as indented JSONC text with its comments, each
element and member on its own line, as `to_pretty_string` writes it.

**Parameters**
- `indent` — the number of spaces per level of nesting
- `ascii_only` — whether to escape every non-ASCII character as `\u`

**Returns**
- the text, without a final line break

**Panics**
- if `indent` is negative ("JsonDocument.to_string needs a non-negative indent")

## parse_document

```pepper
parse_document(text: String, path: String = "", max_depth: ulong = 1000): Result<JsonDocument, JsonError>
```

Parses JSONC text into a `JsonDocument`, keeping its comments.

The text is read as `parse` reads it with `comments = true`: `//` and
`/* */` comments, and a trailing comma after the last element or member.
Use it to change a file people edit, such as a settings file, and write
it back with its comments; use `parse` when the comments do not matter.

**Parameters**
- `text` — the JSONC text
- `path` — the name of the text (a file name, say), which the error's `to_string()` puts first
- `max_depth` — how deeply arrays and objects may nest

**Returns**
- the document, or an error naming the first problem and its line and column
