## The attributes that shape the options `Parser.add_options` declares
## from a struct's fields.

## Sets how a field of an options struct is declared as an option: its
## short name, its help, and whether it is required. A field without it is
## still an option, named after the field.
##
## @example
##     import cli;
##
##     struct Options {
##         [cli.Option("o", "the executable to write")]
##         var output: String = "a.out";
##         [cli.Option("v", "say what is happening")]
##         var verbose: bool;
##     }
[Attribute]
export struct Option {
    ## The one-letter short name, without `-`, or empty for none.
    const short_name: String = "";
    ## What the option does, for the help.
    const help: String = "";
    ## The long name, without `--`; empty for the field's name with each
    ## `_` written `-` (`import_path` is `--import-path`).
    const name: String = "";
    ## What the help calls the value; empty for the long name in capitals.
    const value_name: String = "";
    ## Whether leaving the option out is an error.
    const required: bool = false;
}

## Declares a field of an options struct as the next positional argument
## instead of an option. A `T` field takes one value, required unless the
## field starts with a value (its default; an empty `String` or a null
## `io.Path` is none); a `T?` field takes an optional one; a `T[]` field
## takes every value that is left.
##
## @example
##     import cli;
##
##     struct Options {
##         [cli.Positional("the program's entry file")]
##         var source: String;
##     }
[Attribute]
export struct Positional {
    ## What the argument is, for the help.
    const help: String = "";
    ## What the help and errors call it; empty for the field's name.
    const name: String = "";
    ## Whether leaving it out is an error, even when the field has a
    ## default; for a `T[]` field, whether at least one value must be
    ## given. A `T?` field ignores it.
    const required: bool = false;
}
