## Serialization attributes: how a struct's properties are written to and
## read from text formats.
##
## `json` reads these attributes when it converts a struct (`json.encode`,
## `json.decode`), and other formats will share them, so one set of
## attributes describes a type for every format. Write them above a
## property; `import serialize` brings them in, and `import json` alone is
## enough too, since `json` exports them.
##
## @example
##     import json;
##
##     struct ServerConfig {
##         var host: String;
##         [Name("max-connections")]
##         var max_connections: int;
##         [Required]
##         var port: int;
##         [Ignore]
##         var started_at: long;
##     }

## Writes a property under `value` rather than under its own name.
##
## @example
##     import json;
##
##     struct Limits {
##         [Name("max-connections")]
##         var max_connections: int;
##     }
[Attribute]
export struct Name {
    ## The key the property is written under.
    const value: String;
}

## Leaves a property out: it is not written, and reading leaves it as it
## was.
[Attribute]
export struct Ignore {}

## Makes a missing key an error when reading. Without it, a missing key
## leaves the property at its default.
[Attribute]
export struct Required {}
