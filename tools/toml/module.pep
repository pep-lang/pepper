## TOML: parse a document into a `TomlValue`, look values up and change
## them, write tables back as documents, edit a document in place keeping
## its comments and layout, and convert structs to TOML and back.
##
## Bring it in with `import toml`. Parsing follows TOML 1.0 and checks all
## of its rules; errors carry a line and column, like a compiler's. Tables
## keep their keys in the order they were written.
##
## - `TomlValue` and `TomlDateTime`: the values
## - `parse` and `TomlError`: reading text
## - `TomlDocument` and `parse_document`: changing a file people edit, such
##   as `pep.toml`, without reformatting it
## - `encode`, `decode`, `to_toml`, `from_toml` and `UnknownKeys`: struct
##   conversion, with the `serialize` attributes `json` uses
##
## @example
##     import toml;
##
##     main(): int {
##         var parsed = toml.parse("[package]\nname = \"demo\"\nversion = \"0.1.0\"\n");
##         if (parsed.is_err()) {
##             print(parsed.error().to_string());
##             return 1;
##         }
##         var root = parsed.value();
##         assert(root.lookup("package.name").value().as_string().value() == "demo", "a string");
##         var package = root["package"];
##         package["edition"] = toml.TomlValue.Integer(2026);
##         print(root.to_document());
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import serialize;
import "convert";
import "document";
import "parse";
import "value";

export TomlValue;
export TomlDateTime;
export TomlError;
export parse;
export TomlDocument;
export parse_document;
export UnknownKeys;
export to_toml;
export from_toml;
export encode;
export decode;
