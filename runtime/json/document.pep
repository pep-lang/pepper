## `JsonDocument`: a JSONC document that keeps its comments, so a settings
## file can be read, changed and written back with them.

import "parse";
import "value";

## A JSON value with the comments of the JSONC text it was read from, as
## `parse_document` makes it.
##
## Each comment belongs to a value, by the value's path from the root `$`
## (`$.editor.tab_size`, `$.files[0]`): the comments on the lines before
## a value, or on the line it ends (after its comma), stay with it, and
## those before a closing bracket stay at the end of their array or object.
## `to_string()` writes them back in those places, so text read and
## written unchanged keeps every comment, in the indented layout
## `to_pretty_string` uses.
##
## Change `root` freely. A comment whose value is gone (a removed key, an
## array shortened past it) is not written; one whose path names another
## value afterwards (an element shifted into its index) goes with that
## value.
##
## @example
##     import json;
##
##     var text = "{\n  // The editor.\n  \"tab_size\": 4, // spaces\n  \"wrap\": true\n}";
##     var document = json.parse_document(text).value();
##     document.root["wrap"] = json.JsonValue.Bool(false);
##     assert(
##         document.to_string() == "{\n  // The editor.\n  \"tab_size\": 4, // spaces\n  \"wrap\": false\n}",
##         "the comments stay"
##     );
##     assert(document.comments("$.tab_size")[0] == "// The editor.", "by path");
export struct JsonDocument {
    ## The document's value.
    var root: JsonValue;
    _JsonComments _notes;

    ## Creates a document holding `root`, with no comments.
    ##
    ## @param root the document's value
    construct(root: JsonValue = JsonValue.Null) {
        this.root = root;
        _notes = _JsonComments();
    }

    ## Returns the comments on the lines before the value at `path`, each
    ## with its `//` or `/* */`.
    ##
    ## @param path the value's path from the root: `$`, `$.key`, `$[0]`, or
    ##   `$["a key"]` for a key that is not an identifier
    ## @returns the comments, oldest first; empty when there are none
    comments(path: String): Array<String> {
        var filed = _notes.before.try_get(path);
        var copy = Array<String>();
        if (filed.is_value()) {
            for (var comment in filed.value()) {
                copy.append(comment);
            }
        }
        return copy;
    }

    ## Replaces the comments on the lines before the value at `path`. Each
    ## must be a whole comment, `// ...` (one line) or `/* ... */`.
    ##
    ## @param path the value's path from the root, as for `comments`
    ## @param comments the comments to write before the value; empty
    ##   removes them
    ## @panics if a comment does not start with `//` or `/*` ("a JSONC
    ##   comment starts with '//' or '/*'")
    set_comments(path: String, comments: Array<String>) {
        for (var comment in comments) {
            assert(comment.starts_with("//") || comment.starts_with("/*"), "a JSONC comment starts with '//' or '/*'");
        }
        _notes.before.remove(path);
        _notes.add(_notes.before, path, comments);
    }

    ## Returns the document as indented JSONC text with its comments, each
    ## element and member on its own line, as `to_pretty_string` writes it.
    ##
    ## @param indent the number of spaces per level of nesting
    ## @param ascii_only whether to escape every non-ASCII character as `\u`
    ## @returns the text, without a final line break
    ## @panics if `indent` is negative ("JsonDocument.to_string needs a
    ##   non-negative indent")
    to_string(indent: int = 2, ascii_only: bool = false): String {
        assert(indent >= 0, "JsonDocument.to_string needs a non-negative indent");
        return _json_write_commented(root, _notes, indent + 1, ascii_only);
    }
}

## Parses JSONC text into a `JsonDocument`, keeping its comments.
##
## The text is read as `parse` reads it with `comments = true`: `//` and
## `/* */` comments, and a trailing comma after the last element or member.
## Use it to change a file people edit, such as a settings file, and write
## it back with its comments; use `parse` when the comments do not matter.
##
## @param text the JSONC text
## @param path the name of the text (a file name, say), which the error's
##   `to_string()` puts first
## @param max_depth how deeply arrays and objects may nest
## @returns the document, or an error naming the first problem and its
##   line and column
export parse_document(text: String, path: String = "", max_depth: ulong = 1000): Result<JsonDocument, JsonError> {
    var document = JsonDocument();
    var parsed = _json_parse_commented(text, document._notes, path, max_depth);
    if (parsed.is_err()) {
        return Result<JsonDocument, JsonError>.err(parsed.error());
    }
    document.root = parsed.value();
    return Result<JsonDocument, JsonError>.ok(document);
}
