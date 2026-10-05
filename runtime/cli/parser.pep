## Parser and the handles its declarations return: Flag, Argument and
## ArgumentList.

import [File, Path] from io;
import process;
import "completions";
import "options";

# What a declared option or positional argument holds.
const FLAG_KIND = 0;
const SINGLE_KIND = 1;
const LIST_KIND = 2;

# One declared option or positional argument. The handle a declaration
# returns (Flag, Argument or ArgumentList) shares it, so parsing fills in
# what the handle reads.
struct _CliArgument {
    var name: String = "";
    var short_name: String = "";
    var help: String = "";
    var value_name: String = "";
    var kind: int = 0;
    var positional: bool = false;
    var required: bool = false;
    # Whether the option also applies after a command's name.
    var global: bool = false;
    var default_value: String = "";
    var values: Array<String> = __null;
    var occurrences: int = 0;
    # For a typed value (`option<int>`): whether a text reads as one, what
    # an error says it expects, and an enum's choices. `check` is null for
    # a String, which takes any text.
    var check: (String) => bool = __null;
    var expected: String = "";
    var choices = Array<String>();
    # Whether a shell completes its value as a file name: true for a
    # String or an `io.Path`.
    var names_files: bool = true;

    construct(name: String, short_name: String, help: String, kind: int, positional: bool) {
        this.name = name;
        this.short_name = short_name;
        this.help = help;
        this.kind = kind;
        this.positional = positional;
        values = Array<String>();
    }

    # Whether `text` is a value of its type.
    reads(text: String): bool {
        return check === __null or check(text);
    }

    # How the help and errors name it: `--output`, or `<source>`.
    display(): String {
        if (positional) {
            return "<" + name + ">";
        }
        return "--" + name;
    }

    # The usage line's spelling of it.
    usage(): String {
        if (positional) {
            var shown = required ? "<" + name + ">" : "[" + name + "]";
            return kind == LIST_KIND ? shown + "..." : shown;
        }
        return "--" + name + " <" + value_name + ">";
    }

    # The left column of its line in the help.
    label(): String {
        if (positional) {
            return kind == LIST_KIND ? "<" + name + ">..." : "<" + name + ">";
        }
        var text = short_name.is_empty ? "    --" + name : "-" + short_name + ", --" + name;
        if (kind != FLAG_KIND) {
            text = text + " <" + value_name + ">";
        }
        return text;
    }

    # The right column of its line in the help.
    description(): String {
        var text = help;
        if (!default_value.is_empty) {
            text = _cli_join_words(text, "[default: " + default_value + "]");
        }
        if (!choices.is_empty) {
            text = _cli_join_words(text, "[possible values: " + ", ".join(choices) + "]");
        }
        if (required and !positional) {
            text = _cli_join_words(text, "[required]");
        }
        if (kind == LIST_KIND and !positional) {
            text = _cli_join_words(text, "[repeatable]");
        }
        return text;
    }
}

# `a` and `b` separated by a space, or whichever is not empty.
_cli_join_words(a: String, b: String): String {
    if (a.is_empty) {
        return b;
    }
    return a + " " + b;
}

## Declares a program's command-line interface and parses its arguments.
##
## Declare each option and positional argument with `flag`, `option`,
## `multiple`, `positional` and `positionals`; each returns a handle that
## reads its value once `parse` has run. `parse` also writes the help
## (`--help`), the version (`--version`) and clang-style errors, all from
## the declarations.
##
## Options have a long name (`--output`) and an optional one-letter short
## name (`-o`). A value follows as `--output a.out`, `--output=a.out`,
## `-o a.out` or `-oa.out`; short flags combine (`-vq` is `-v -q`), and
## `--` ends the options, so every argument after it is positional. A value
## is taken as it is, even when it starts with `-`. When an option that
## takes one value is given twice, the last value wins.
##
## Subcommands (`git add`, `pep-package update`) are parsers of their own,
## made with `command`. Options before the command's name belong to this
## parser, and everything after it to the command's.
##
## @example
##     import cli;
##
##     main(args: String[]): int {
##         var parser = cli.Parser("pepper", "Compiles a Pepper program", version = "0.2.1");
##         var output = parser.option("output", "o", "the executable to write", default_value = "a.out");
##         var imports = parser.multiple("import-path", "I", "a directory to search for modules");
##         var verbose = parser.flag("verbose", "v", "say what is happening");
##         var source = parser.positional("source", "the program's entry file");
##         if (!parser.parse(args)) {
##             return 2;
##         }
##         print($"{source.value()} -> {output.value()}");
##         return 0;
##     }
export struct Parser {
    var _name: String = "";
    var _path: String = "";
    var _about: String = "";
    var _version: String = "";
    var _options: Array<_CliArgument> = __null;
    var _positionals: Array<_CliArgument> = __null;
    var _commands: Array<Parser> = __null;
    var _selected: bool = false;
    var _failed_usage: String = "";
    var _failed_path: String = "";
    var _binders: Array<() => void> = __null;
    # The options of the parsers this one is a command of, nearest first,
    # whose global ones apply here too. Their arrays, not the parsers, so
    # a command holds no reference back to its parent.
    var _ancestor_options = Array<Array<_CliArgument>>();

    ## Makes a parser for the program `name`.
    ##
    ## @param name the program's name, as the help and errors show it
    ## @param about a sentence on what the program does, the help's first line
    ## @param version the program's version; when not empty, `--version` and
    ##   `-V` print `name version`
    construct(name: String, about: String = "", version: String = "") {
        _name = name;
        _path = name;
        _about = about;
        _version = version;
        _options = Array<_CliArgument>();
        _positionals = Array<_CliArgument>();
        _commands = Array<Parser>();
        _binders = Array<() => void>();
    }

    ## Declares an option that takes no value, such as `--verbose`.
    ##
    ## @param name the long name, without `--`
    ## @param short_name the one-letter short name, without `-`, or empty for none
    ## @param help what the option does, for the help
    ## @param global whether the flag may also be given after the name of a
    ##   command, at any depth (`pkg add -v x` as well as `pkg -v add x`)
    ## @returns the handle that tells whether the flag was given
    ## @panics if `name` or `short_name` is invalid or already declared, here,
    ##   as a global option of a parser this one is a command of, or (for a
    ##   global flag) in one of its commands
    flag(name: String, short_name: String = "", help: String = "", global: bool = false): Flag {
        var declared = _declare_option(name, short_name, help, FLAG_KIND);
        if (global) {
            _make_global(declared);
        }
        return Flag(declared);
    }

    ## Declares an option that takes one String value, such as
    ## `--output a.out`. `option<T>` declares one whose value is a number,
    ## a path or an enum case.
    ##
    ## @param name the long name, without `--`
    ## @param short_name the one-letter short name, without `-`, or empty for none
    ## @param help what the option sets, for the help
    ## @param value_name what the help calls the value; empty for the long
    ##   name in capitals (`OUTPUT`)
    ## @param default_value the value when the option is not given; empty for none
    ## @param required whether leaving the option out is an error
    ## @param global whether the option may also be given after the name of
    ##   a command, at any depth
    ## @returns the handle that reads the value
    ## @panics if `name` or `short_name` is invalid or already declared
    option(
        name: String,
        short_name: String = "",
        help: String = "",
        value_name: String = "",
        default_value: String = "",
        required: bool = false,
        global: bool = false
    ): Argument<String> {
        return this.option<String>(name, short_name, help, value_name, default_value, required, global);
    }

    ## Declares an option that takes one value of type `T`, such as
    ## `--jobs 4` for `option<int>`. A value that does not read as a `T`
    ## fails the parse: `invalid value 'x' for '--jobs': expected an
    ## integer`.
    ##
    ## `T` may be `String`, an integer type, `float`, `double`, `io.Path`,
    ## or an enum whose cases carry no values; a case is written in kebab
    ## case (`DebugInfo` is `debug-info`), and the help lists them.
    ##
    ## @typeParam T the type of the value
    ## @param name the long name, without `--`
    ## @param short_name the one-letter short name, without `-`, or empty for none
    ## @param help what the option sets, for the help
    ## @param value_name what the help calls the value; empty for the long
    ##   name in capitals (`JOBS`)
    ## @param default_value the value when the option is not given, written
    ##   as on the command line (`"4"`); empty for none
    ## @param required whether leaving the option out is an error
    ## @param global whether the option may also be given after the name of
    ##   a command, at any depth
    ## @returns the handle that reads the value
    ## @panics if `name` or `short_name` is invalid or already declared, or
    ##   if `default_value` does not read as a `T`
    ## @example
    ##     var jobs = parser.option<int>("jobs", "j", "how many at once", default_value = "4");
    option<T>(
        name: String,
        short_name: String = "",
        help: String = "",
        value_name: String = "",
        default_value: String = "",
        required: bool = false,
        global: bool = false
    ): Argument<T> {
        var declared = _declare_option(name, short_name, help, SINGLE_KIND);
        declared.value_name = value_name.is_empty ? name.upper().replace("-", "_") : value_name;
        declared.default_value = default_value;
        declared.required = required;
        if (global) {
            _make_global(declared);
        }
        _cli_type<T>(declared);
        return Argument<T>(declared);
    }

    ## Declares an option that may be given any number of times, each with a
    ## String value, such as `-I src -I lib`. `multiple<T>` declares one
    ## whose values are numbers, paths or enum cases.
    ##
    ## @param name the long name, without `--`
    ## @param short_name the one-letter short name, without `-`, or empty for none
    ## @param help what the option adds, for the help
    ## @param value_name what the help calls the value; empty for the long
    ##   name in capitals (`IMPORT_PATH`)
    ## @param required whether leaving the option out is an error
    ## @param global whether the option may also be given after the name of
    ##   a command, at any depth
    ## @returns the handle that reads the values, in the order given
    ## @panics if `name` or `short_name` is invalid or already declared
    multiple(
        name: String,
        short_name: String = "",
        help: String = "",
        value_name: String = "",
        required: bool = false,
        global: bool = false
    ): ArgumentList<String> {
        return this.multiple<String>(name, short_name, help, value_name, required, global);
    }

    ## Declares an option that may be given any number of times, each with a
    ## value of type `T`, such as `-I src -I lib` for `multiple<io.Path>`.
    ## `T` is one of the types `option<T>` takes.
    ##
    ## @typeParam T the type of each value
    ## @param name the long name, without `--`
    ## @param short_name the one-letter short name, without `-`, or empty for none
    ## @param help what the option adds, for the help
    ## @param value_name what the help calls the value; empty for the long
    ##   name in capitals (`IMPORT_PATH`)
    ## @param required whether leaving the option out is an error
    ## @param global whether the option may also be given after the name of
    ##   a command, at any depth
    ## @returns the handle that reads the values, in the order given
    ## @panics if `name` or `short_name` is invalid or already declared
    multiple<T>(
        name: String,
        short_name: String = "",
        help: String = "",
        value_name: String = "",
        required: bool = false,
        global: bool = false
    ): ArgumentList<T> {
        var declared = _declare_option(name, short_name, help, LIST_KIND);
        declared.value_name = value_name.is_empty ? name.upper().replace("-", "_") : value_name;
        declared.required = required;
        if (global) {
            _make_global(declared);
        }
        _cli_type<T>(declared);
        return ArgumentList<T>(declared);
    }

    ## Declares the next positional argument, with a String value.
    ## Positional arguments are filled in the order they are declared.
    ## `positional<T>` declares one whose value is a number, a path or an
    ## enum case.
    ##
    ## @param name what the help and errors call it
    ## @param help what it is, for the help
    ## @param required whether leaving it out is an error
    ## @param default_value the value when it is left out; empty for none
    ## @returns the handle that reads the value
    ## @panics if `name` is empty or already declared, if a required argument
    ##   follows an optional one, if it follows `positionals`, or if the
    ##   parser has commands
    positional(name: String, help: String = "", required: bool = true, default_value: String = ""): Argument<String> {
        return this.positional<String>(name, help, required, default_value);
    }

    ## Declares the next positional argument, with a value of type `T`.
    ## `T` is one of the types `option<T>` takes.
    ##
    ## @typeParam T the type of the value
    ## @param name what the help and errors call it
    ## @param help what it is, for the help
    ## @param required whether leaving it out is an error
    ## @param default_value the value when it is left out, written as on the
    ##   command line; empty for none
    ## @returns the handle that reads the value
    ## @panics if `name` is empty or already declared, if a required argument
    ##   follows an optional one, if it follows `positionals`, if the parser
    ##   has commands, or if `default_value` does not read as a `T`
    positional<T>(name: String, help: String = "", required: bool = true, default_value: String = ""): Argument<T> {
        var declared = _declare_positional(name, help, SINGLE_KIND, required);
        declared.default_value = default_value;
        _cli_type<T>(declared);
        return Argument<T>(declared);
    }

    ## Declares a positional argument that takes every remaining value, such
    ## as a list of files. It must be the last positional argument.
    ## `positionals<T>` declares one whose values are numbers, paths or enum
    ## cases.
    ##
    ## @param name what the help and errors call it
    ## @param help what the values are, for the help
    ## @param required whether at least one value must be given
    ## @returns the handle that reads the values, in the order given
    ## @panics if `name` is empty or already declared, if it follows
    ##   `positionals`, or if the parser has commands
    positionals(name: String, help: String = "", required: bool = false): ArgumentList<String> {
        return this.positionals<String>(name, help, required);
    }

    ## Declares a positional argument that takes every remaining value, each
    ## of type `T`, such as a list of files for `positionals<io.Path>`. It
    ## must be the last positional argument. `T` is one of the types
    ## `option<T>` takes.
    ##
    ## @typeParam T the type of each value
    ## @param name what the help and errors call it
    ## @param help what the values are, for the help
    ## @param required whether at least one value must be given
    ## @returns the handle that reads the values, in the order given
    ## @panics if `name` is empty or already declared, if it follows
    ##   `positionals`, or if the parser has commands
    positionals<T>(name: String, help: String = "", required: bool = false): ArgumentList<T> {
        var declared = _declare_positional(name, help, LIST_KIND, required);
        _cli_type<T>(declared);
        return ArgumentList<T>(declared);
    }

    ## Declares a subcommand, such as `add` in `pep-package add NAME`, and
    ## returns its parser, on which to declare its own options and
    ## arguments.
    ##
    ## A parser with commands requires one: the first argument that is not
    ## an option names it, and the arguments after it go to its parser.
    ## After `parse`, `is_selected` on the command's parser tells whether
    ## it was the one given.
    ##
    ## @param name the command's name
    ## @param about what the command does, for the help
    ## @returns the command's parser
    ## @panics if `name` is empty, starts with `-` or is already declared, or
    ##   if this parser has positional arguments
    command(name: String, about: String = ""): Parser {
        assert(!name.is_empty and !name.starts_with("-"), "cli: invalid command name '" + name + "'");
        assert(_positionals.is_empty, "cli: '" + _path + "' has positional arguments, so it cannot have commands");
        for (var existing in _commands) {
            assert(existing._name != name, "cli: command '" + name + "' declared twice");
        }
        var command = Parser(name, about, _version);
        command._path = _path + " " + name;
        command._ancestor_options.append(_options);
        command._ancestor_options.append_all(_ancestor_options);
        _commands.append(command);
        return command;
    }

    ## Declares an option or positional argument for each public field of
    ## `options`, and has every successful parse store the values in those
    ## fields.
    ##
    ## A field's type picks what it declares: `bool` is a flag, `String` an
    ## option with one value, `String?` one that may be left out, and
    ## `String[]` one that may be given many times. An option is named after
    ## its field, with each `_` written `-` (`import_path` is
    ## `--import-path`); `[cli.Option]` on a field gives it a short name,
    ## help, another name, or makes it required. `[cli.Positional]` makes a
    ## field the next positional argument instead.
    ##
    ## A `String` field that holds a value when this is called keeps it as
    ## the default; an empty one has no default, so leaving the option out
    ## leaves it empty, or is an error for a positional argument. Every
    ## parse sets every field: a flag to whether it was given, a list to the
    ## values given.
    ##
    ## The declarations are the same as the builder methods make, so the
    ## help and errors read the same, and the two styles mix on one parser.
    ##
    ## @typeParam T the options struct
    ## @param options the struct whose fields to declare and fill in
    ## @example
    ##     import cli;
    ##
    ##     struct Options {
    ##         [cli.Option("o", "the executable to write")]
    ##         var output: String = "a.out";
    ##         [cli.Option("v", "say what is happening")]
    ##         var verbose: bool;
    ##         [cli.Positional("the program's entry file")]
    ##         var source: String;
    ##     }
    ##
    ##     main(args: String[]): int {
    ##         var options = Options();
    ##         var parser = cli.Parser("pepper", "Compiles a Pepper program");
    ##         parser.add_options(options);
    ##         if (!parser.parse(args)) {
    ##             return 2;
    ##         }
    ##         print($"{options.source} -> {options.output}");
    ##         return 0;
    ##     }
    add_options<T>(options: T) {
        var declared = Array<_CliArgument>();
        static (this, options, declared) {
            reflect.assert(reflect.is_struct<T>(), $"'add_options' needs a struct, not '{reflect.name<T>()}'");
            for (var field in reflect.properties<T>()) {
                # A shallow check, to name the field; the type inside a
                # `T?` or `T[]` is checked when it is declared.
                var list = field.type_name.starts_with("Array<") or field.type_name.ends_with("[]");
                var other_struct = reflect.is_struct<field.Type>()
                    and !list
                    and !reflect.is_same<field.Type, String>()
                    and !reflect.is_same<field.Type, Path>();
                reflect.assert(
                    !other_struct and !reflect.is_trait<field.Type>(),
                    $"'add_options' cannot declare field '{field.name}' of type '{field.type_name}'; use bool, String, a number type, io.Path or an enum, or one of those as T? or T[]"
                );
                if (field.has_attribute<Positional>()) {
                    var positional = field.attribute<Positional>();
                    reflect.assert(
                        !reflect.is_same<field.Type, bool>(), $"positional argument '{field.name}' cannot be a bool"
                    );
                    var name = positional.name.is_empty ? field.name : positional.name;
                    declared.append(
                        _cli_field_positional(this, name, positional.help, positional.required, field.get(options))
                    );
                } else {
                    var short_name = "";
                    var help = "";
                    var name = "";
                    var value_name = "";
                    var required = false;
                    var global = false;
                    if (field.has_attribute<Option>()) {
                        var option = field.attribute<Option>();
                        short_name = option.short_name;
                        help = option.help;
                        name = option.name;
                        value_name = option.value_name;
                        required = option.required;
                        global = option.global;
                    }
                    declared.append(
                        _cli_field_option(
                            this,
                            _cli_long_name(field.name, name),
                            short_name,
                            help,
                            value_name,
                            required,
                            field.get(options)
                        )
                    );
                    if (global) {
                        this._make_global(declared.last());
                    }
                }
            }
        }
        _binders.append(() => _cli_store<T>(options, declared));
    }

    ## Whether the last `parse` reached this parser: whether this command
    ## was given. The top-level parser is selected whenever its arguments
    ## were parsed.
    var is_selected: bool {
        get {
            return _selected;
        }
    }

    ## Returns the one-line usage, such as
    ## `usage: pepper [OPTIONS] <source>`.
    ##
    ## @returns the usage line, without a line break
    usage(): String {
        var text = "usage: " + _path + " [OPTIONS]";
        for (var option in _options) {
            if (option.required) {
                text = text + " " + option.usage();
            }
        }
        for (var positional in _positionals) {
            text = text + " " + positional.usage();
        }
        if (!_commands.is_empty) {
            text = text + " <COMMAND>";
        }
        return text;
    }

    ## Returns the help that `--help` prints: what the program does, the
    ## usage, and a line for each argument, option and command.
    ##
    ## @returns the help text, ending in a line break
    help(): String {
        var text = StringBuilder();
        if (!_about.is_empty) {
            text.append(_about).append("\n\n");
        }
        text.append(usage()).append("\n");
        var labels = Array<String>();
        var descriptions = Array<String>();
        for (var positional in _positionals) {
            labels.append(positional.label());
            descriptions.append(positional.description());
        }
        _append_section(text, "Arguments", labels, descriptions);
        labels.clear();
        descriptions.clear();
        for (var command in _commands) {
            labels.append(command._name);
            descriptions.append(command._about);
        }
        _append_section(text, "Commands", labels, descriptions);
        labels.clear();
        descriptions.clear();
        for (var option in _options) {
            labels.append(option.label());
            descriptions.append(option.description());
        }
        for (var option in _inherited_options()) {
            labels.append(option.label());
            descriptions.append(option.description());
        }
        labels.append(_find_short("h") === __null ? "-h, --help" : "    --help");
        descriptions.append("show this help");
        if (!_version.is_empty) {
            labels.append(_find_short("V") === __null ? "-V, --version" : "    --version");
            descriptions.append("show the version");
        }
        _append_section(text, "Options", labels, descriptions);
        return text.to_string();
    }

    ## Returns a script that completes this program's command line in
    ## `shell`: its options, commands and enum choices, and file names
    ## where a value is a `String` or an `io.Path`. A program usually
    ## prints it from a command of its own (`pkg completions bash`), for
    ## the user to install where `Shell`'s cases say.
    ##
    ## Call it on the program's parser, after the declarations.
    ##
    ## @param shell the shell the script is for
    ## @returns the script, ending in a line break
    ## @example
    ##     var parser = cli.Parser("pkg");
    ##     var shell = parser.option<cli.Shell>("completions", help = "print a completion script");
    ##     if (!parser.parse(args)) {
    ##         return 2;
    ##     }
    ##     if (shell.is_set) {
    ##         print(parser.completions(shell.value()));
    ##     }
    completions(shell: Shell): String {
        var nodes = Array<_CliNode>();
        _cli_nodes(this, _path, nodes);
        if (shell == Shell.Bash) {
            return _cli_bash(nodes);
        }
        if (shell == Shell.Zsh) {
            return _cli_zsh(nodes);
        }
        if (shell == Shell.Fish) {
            return _cli_fish(nodes);
        }
        return _cli_powershell(nodes);
    }

    ## Parses `args` and fills in every handle, or reports the problem.
    ##
    ## Writes nothing. Use it to handle errors, help and the version
    ## yourself; `parse` does it the usual way.
    ##
    ## @param args the arguments as `main` receives them: the program's
    ##   name, then its arguments
    ## @returns some text when `--help` or `--version` was given (the
    ##   program should print it and exit with 0), none when the arguments
    ##   were parsed, or an error when they are wrong, with a clang-style
    ##   message such as `missing value for '-o'`
    try_parse(args: String[]): Result<String?> {
        _failed_usage = "";
        _failed_path = _path;
        var result = _parse(args, 1, this);
        if (result.is_ok() and !result.value()) {
            _bind();
        }
        return result;
    }

    ## Parses `args` and fills in every handle.
    ##
    ## For `--help` or `--version` it prints the text to standard output and
    ## ends the program with status 0. When the arguments are wrong it
    ## writes the error, the usage and a hint to standard error, such as
    ##
    ##     pepper: error: missing value for '-o'
    ##     usage: pepper [OPTIONS] <source>
    ##     Run 'pepper --help' for more information.
    ##
    ## and returns false; exit with status 2, as the example does.
    ##
    ## @param args the arguments as `main` receives them: the program's
    ##   name, then its arguments
    ## @returns true when the arguments were parsed, false after an error
    parse(args: String[]): bool {
        var result = try_parse(args);
        if (result.is_err()) {
            File.stderr().write_all(
                _name
                    + ": error: "
                    + result.error().message
                    + "\n"
                    + _failed_usage
                    + "\n"
                    + "Run '"
                    + _failed_path
                    + " --help' for more information.\n"
            );
            return false;
        }
        var output = result.value();
        if (output) {
            File.stdout().write_all(output.value());
            process.exit(0);
        }
        return true;
    }

    # Stores what the last parse found in the options structs given to
    # `add_options`, here and in the command that was selected.
    _bind() {
        for (var binder in _binders) {
            binder();
        }
        for (var command in _commands) {
            if (command._selected) {
                command._bind();
            }
        }
    }

    # Declares an option after checking its names.
    _declare_option(name: String, short_name: String, help: String, kind: int): _CliArgument {
        assert(
            !name.is_empty and !name.starts_with("-") and !name.contains("="), "cli: invalid option name '" + name + "'"
        );
        assert(name != "help" and (name != "version" or _version.is_empty), "cli: option '--" + name + "' is built in");
        assert(
            short_name.is_empty or (short_name.size == 1 and short_name != "-" and short_name != "="),
            "cli: invalid short name '" + short_name + "' for '--" + name + "': it must be one character"
        );
        assert(_find_option(name) === __null, "cli: option '--" + name + "' declared twice");
        assert(
            short_name.is_empty or _find_short(short_name) === __null,
            "cli: short name '-" + short_name + "' declared twice"
        );
        var declared = _CliArgument(name, short_name, help, kind, false);
        _options.append(declared);
        return declared;
    }

    # Declares a positional argument after checking where it may go.
    _declare_positional(name: String, help: String, kind: int, required: bool): _CliArgument {
        assert(!name.is_empty, "cli: a positional argument needs a name");
        assert(_commands.is_empty, "cli: '" + _path + "' has commands, so it cannot have positional arguments");
        for (var existing in _positionals) {
            assert(existing.name != name, "cli: positional argument '" + name + "' declared twice");
            assert(
                existing.kind != LIST_KIND,
                "cli: '" + name + "' follows '" + existing.name + "', which takes every value"
            );
            assert(
                existing.required or !required,
                "cli: required argument '" + name + "' follows optional argument '" + existing.name + "'"
            );
        }
        var declared = _CliArgument(name, "", help, kind, true);
        declared.required = required;
        _positionals.append(declared);
        return declared;
    }

    # The option named `name` here, or a global one of a parser this one
    # is a command of; null for none.
    _find_option(name: String): _CliArgument {
        for (var option in _options) {
            if (option.name == name) {
                return option;
            }
        }
        for (var options in _ancestor_options) {
            for (var option in options) {
                if (option.global and option.name == name) {
                    return option;
                }
            }
        }
        return __null;
    }

    # The option with short name `short_name`, found as `_find_option`
    # finds one.
    _find_short(short_name: String): _CliArgument {
        for (var option in _options) {
            if (option.short_name == short_name) {
                return option;
            }
        }
        for (var options in _ancestor_options) {
            for (var option in options) {
                if (option.global and option.short_name == short_name) {
                    return option;
                }
            }
        }
        return __null;
    }

    # Makes `declared`, an option of this parser, global, after checking
    # that no command below declares its names.
    _make_global(declared: _CliArgument) {
        declared.global = true;
        for (var command in _commands) {
            command._check_names_free(declared);
        }
    }

    # Panics if this parser or a command below it declares a name of the
    # global option `global`.
    _check_names_free(global: _CliArgument) {
        for (var option in _options) {
            assert(option.name != global.name, "cli: option '--" + global.name + "' declared twice");
            assert(
                global.short_name.is_empty or option.short_name != global.short_name,
                "cli: short name '-" + global.short_name + "' declared twice"
            );
        }
        for (var command in _commands) {
            command._check_names_free(global);
        }
    }

    # The global options of the parsers this one is a command of, nearest
    # first.
    _inherited_options(): Array<_CliArgument> {
        var inherited = Array<_CliArgument>();
        for (var options in _ancestor_options) {
            for (var option in options) {
                if (option.global) {
                    inherited.append(option);
                }
            }
        }
        return inherited;
    }

    # Clears what the last parse filled in, here and in every command.
    _reset() {
        _selected = false;
        for (var option in _options) {
            option.values.clear();
            option.occurrences = 0;
        }
        for (var positional in _positionals) {
            positional.values.clear();
        }
        for (var command in _commands) {
            command._reset();
        }
    }

    # Parses `args` from `start`; `root` records the usage of the parser an
    # error came from. Recurses once per command level, which the program
    # declares, so the input cannot make it deep.
    _parse(args: String[], start: ulong, root: Parser): Result<String?> {
        _reset();
        _selected = true;
        ulong index = start;
        ulong position = 0;
        var only_positionals = false;
        while (index < args.count) {
            var argument = args[index];
            index += 1;
            if (!only_positionals and argument == "--") {
                only_positionals = true;
            } else if (!only_positionals and argument.starts_with("--")) {
                var body = argument.substr_bytes(2, argument.size - 2);
                var name = body;
                var attached = Optional<String>.Empty;
                var split = body.split_once("=");
                if (split) {
                    var (before, after) = split.value();
                    name = before;
                    attached = Optional<String>.Value(after);
                }
                var option = _find_option(name);
                if (option === __null) {
                    if (name == "help") {
                        return Result<String?>.ok(Optional<String>.Value(help()));
                    }
                    if (name == "version" and !_version.is_empty) {
                        return Result<String?>.ok(Optional<String>.Value(root._name + " " + _version + "\n"));
                    }
                    return _fail(root, _unknown_option(name));
                }
                if (option.kind == FLAG_KIND) {
                    if (attached) {
                        return _fail(root, "option '--" + name + "' takes no value");
                    }
                    option.occurrences += 1;
                } else {
                    if (!attached and index >= args.count) {
                        return _fail(root, "missing value for '--" + name + "'");
                    }
                    var value = attached ? attached.value() : args[index];
                    if (!attached) {
                        index += 1;
                    }
                    if (!_store(option, value)) {
                        return _fail(root, _invalid_value(option, value, "--" + name));
                    }
                }
            } else if (!only_positionals and argument.starts_with("-") and argument.size > 1) {
                ulong at = 1;
                while (at < argument.size) {
                    var letter = _letter_at(argument, at);
                    at += letter.size;
                    var option = _find_short(letter);
                    if (option === __null) {
                        if (letter == "h") {
                            return Result<String?>.ok(Optional<String>.Value(help()));
                        }
                        if (letter == "V" and !_version.is_empty) {
                            return Result<String?>.ok(Optional<String>.Value(root._name + " " + _version + "\n"));
                        }
                        return _fail(root, "unknown option '-" + letter + "'");
                    }
                    if (option.kind == FLAG_KIND) {
                        option.occurrences += 1;
                        continue;
                    }
                    # The rest of the argument is the value (`-oa.out`, or
                    # `-o=a.out`), else the next argument is.
                    var value = argument.substr_bytes(at, argument.size - at);
                    if (value.starts_with("=")) {
                        value = value.substr_bytes(1, value.size - 1);
                    } else if (value.is_empty) {
                        if (index >= args.count) {
                            return _fail(root, "missing value for '-" + letter + "'");
                        }
                        value = args[index];
                        index += 1;
                    }
                    if (!_store(option, value)) {
                        return _fail(root, _invalid_value(option, value, "-" + letter));
                    }
                    break;
                }
            } else if (!_commands.is_empty) {
                var command = _find_command(argument);
                if (command === __null) {
                    return _fail(root, "unknown command '" + argument + "'" + _command_suggestion(argument));
                }
                var missing = _check_required(root);
                if (missing.is_err()) {
                    return missing;
                }
                return command._parse(args, index, root);
            } else if (position < _positionals.count) {
                var positional = _positionals[position];
                if (!_store(positional, argument)) {
                    return _fail(root, _invalid_value(positional, argument, positional.display()));
                }
                if (positional.kind != LIST_KIND) {
                    position += 1;
                }
            } else {
                return _fail(root, "unexpected argument '" + argument + "'");
            }
        }
        var missing = _check_required(root);
        if (missing.is_err()) {
            return missing;
        }
        missing = _check_required_globals(root);
        if (missing.is_err()) {
            return missing;
        }
        for (var positional in _positionals) {
            if (positional.required and positional.values.is_empty) {
                return _fail(root, "missing required argument '" + positional.display() + "'");
            }
        }
        if (!_commands.is_empty) {
            return _fail(root, "missing command: expected " + _command_names());
        }
        return Result<String?>.ok(Optional<String>.Empty);
    }

    # An error for a required option of this parser left out. A global one
    # may still come after a command's name, so it is checked by
    # `_check_required_globals` at the end.
    _check_required(root: Parser): Result<String?> {
        for (var option in _options) {
            if (option.required and !option.global and option.values.is_empty) {
                return _fail(root, "missing required option '--" + option.name + "'");
            }
        }
        return Result<String?>.ok(Optional<String>.Empty);
    }

    # An error for a required global option, here or of a parser this one
    # is a command of, left out.
    _check_required_globals(root: Parser): Result<String?> {
        for (var option in _options) {
            if (option.required and option.global and option.values.is_empty) {
                return _fail(root, "missing required option '--" + option.name + "'");
            }
        }
        for (var option in _inherited_options()) {
            if (option.required and option.values.is_empty) {
                return _fail(root, "missing required option '--" + option.name + "'");
            }
        }
        return Result<String?>.ok(Optional<String>.Empty);
    }

    # Stores a value for `option`, where the last one wins unless it is
    # repeatable, or returns false when it is not a value of its type.
    _store(option: _CliArgument, value: String): bool {
        if (!option.reads(value)) {
            return false;
        }
        if (option.kind == SINGLE_KIND and !option.positional) {
            option.values.clear();
        }
        option.values.append(value);
        return true;
    }

    # "invalid value 'x' for '--jobs': expected an integer", for a value
    # given as `spelling`.
    _invalid_value(option: _CliArgument, value: String, spelling: String): String {
        return "invalid value '" + value + "' for '" + spelling + "': expected " + option.expected;
    }

    # The error `message`, noting this parser's usage for `parse` to print.
    _fail(root: Parser, message: String): Result<String?> {
        root._failed_usage = usage();
        root._failed_path = _path;
        return Result<String?>.err(Error(message));
    }

    _find_command(name: String): Parser {
        for (var command in _commands) {
            if (command._name == name) {
                return command;
            }
        }
        return __null;
    }

    # `'add', 'remove' or 'update'`.
    _command_names(): String {
        var names = Array<String>();
        for (var command in _commands) {
            names.append(command._name);
        }
        return _cli_quoted_list(names);
    }

    # "unknown option '--outptu'; did you mean '--output'?"
    _unknown_option(name: String): String {
        var message = "unknown option '--" + name + "'";
        var names = Array<String>();
        for (var option in _options) {
            names.append(option.name);
        }
        for (var option in _inherited_options()) {
            names.append(option.name);
        }
        names.append("help");
        var best = closest(name, names);
        return best.is_value() ? message + "; did you mean '--" + best.value() + "'?" : message;
    }

    _command_suggestion(name: String): String {
        var names = Array<String>();
        for (var command in _commands) {
            names.append(command._name);
        }
        var best = closest(name, names);
        return best.is_value() ? "; did you mean '" + best.value() + "'?" : "";
    }

    # The character of `argument` whose UTF-8 sequence starts at byte `at`,
    # for an error message.
    _letter_at(argument: String, at: ulong): String {
        ulong end = at + 1;
        while (end < argument.size and (argument.byte_at(end) & 0xC0) == 0x80) {
            end += 1;
        }
        return argument.substr_bytes(at, end - at);
    }

    # Appends a titled two-column section of the help, or nothing when
    # `labels` is empty.
    _append_section(text: StringBuilder, title: String, labels: Array<String>, descriptions: Array<String>) {
        if (labels.is_empty) {
            return;
        }
        ulong width = 0;
        for (var label in labels) {
            if (label.size > width) {
                width = label.size;
            }
        }
        text.append("\n").append(title).append(":\n");
        ulong index = 0;
        while (index < labels.count) {
            var label = labels[index];
            var description = descriptions[index];
            text.append("  ").append(label);
            if (!description.is_empty) {
                text.append(" ".repeat(width - label.size + 2)).append(description);
            }
            text.append("\n");
            index += 1;
        }
    }
}

## Returns the candidate closest to a misspelled `name`, for a "did you
## mean" suggestion: the one the fewest single-byte insertions, deletions
## and substitutions turn `name` into, when that is at most 2. Of equally
## close candidates the first wins.
##
## @param name the name that matched nothing
## @param candidates the names it could have meant
## @returns the closest candidate, or none when none is within 2 edits
## @example
##     var names = Array<String>();
##     names.append("build");
##     names.append("fmt");
##     var best = cli.closest("buidl", names);   # some("build")
export closest(name: String, candidates: Array<String>): String? {
    var best = Optional<String>.Empty;
    var best_distance = 3;
    for (var candidate in candidates) {
        var distance = _cli_edit_distance(name, candidate);
        if (distance < best_distance) {
            best = Optional<String>.Value(candidate);
            best_distance = distance;
        }
    }
    return best;
}

# The number of single-byte insertions, deletions and substitutions that
# turn `a` into `b`, for suggesting a name close to a misspelled one.
_cli_edit_distance(a: String, b: String): int {
    var previous = Array<int>();
    var current = Array<int>();
    ulong j = 0;
    while (j <= b.size) {
        previous.append(j as int);
        current.append(0);
        j += 1;
    }
    ulong i = 1;
    while (i <= a.size) {
        current[0] = i as int;
        j = 1;
        while (j <= b.size) {
            var cost = a.byte_at(i - 1) == b.byte_at(j - 1) ? 0 : 1;
            var best = previous[j - 1] + cost;
            if (previous[j] + 1 < best) {
                best = previous[j] + 1;
            }
            if (current[j - 1] + 1 < best) {
                best = current[j - 1] + 1;
            }
            current[j] = best;
            j += 1;
        }
        var swap = previous;
        previous = current;
        current = swap;
        i += 1;
    }
    return previous[b.size];
}

# Declares the flag for a `bool` field of an options struct.
_cli_field_option(
    parser: Parser, name: String, short_name: String, help: String, value_name: String, required: bool, current: bool
): _CliArgument {
    return parser._declare_option(name, short_name, help, FLAG_KIND);
}

# Declares the option for a `T` field of an options struct, whose
# starting value is the default (none for an empty String or a null).
_cli_field_option<T>(
    parser: Parser, name: String, short_name: String, help: String, value_name: String, required: bool, current: T
): _CliArgument {
    var declared = _cli_field_value_option(parser, name, short_name, help, value_name, required, SINGLE_KIND);
    declared.default_value = _cli_text<T>(current);
    _cli_type<T>(declared);
    return declared;
}

# Declares the option for a `T?` field of an options struct.
_cli_field_option<T>(
    parser: Parser, name: String, short_name: String, help: String, value_name: String, required: bool, current: T?
): _CliArgument {
    var declared = _cli_field_value_option(parser, name, short_name, help, value_name, required, SINGLE_KIND);
    _cli_type<T>(declared);
    return declared;
}

# Declares the repeatable option for a `T[]` field of an options struct.
_cli_field_option<T>(
    parser: Parser,
    name: String,
    short_name: String,
    help: String,
    value_name: String,
    required: bool,
    current: Array<T>
): _CliArgument {
    var declared = _cli_field_value_option(parser, name, short_name, help, value_name, required, LIST_KIND);
    _cli_type<T>(declared);
    return declared;
}

# Declares an option that takes a value, for a field of an options struct.
_cli_field_value_option(
    parser: Parser, name: String, short_name: String, help: String, value_name: String, required: bool, kind: int
): _CliArgument {
    var declared = parser._declare_option(name, short_name, help, kind);
    declared.value_name = value_name.is_empty ? name.upper().replace("-", "_") : value_name;
    declared.required = required;
    return declared;
}

# Declares a positional `T` field of an options struct. Its starting
# value is the default, so it is required only when it has none or
# `required` is set.
_cli_field_positional<T>(parser: Parser, name: String, help: String, required: bool, current: T): _CliArgument {
    var fallback = _cli_text<T>(current);
    var declared = parser._declare_positional(name, help, SINGLE_KIND, required or fallback.is_empty);
    declared.default_value = fallback;
    _cli_type<T>(declared);
    return declared;
}

# Declares a positional `T?` field of an options struct, which may be
# left out.
_cli_field_positional<T>(parser: Parser, name: String, help: String, required: bool, current: T?): _CliArgument {
    var declared = parser._declare_positional(name, help, SINGLE_KIND, false);
    _cli_type<T>(declared);
    return declared;
}

# Declares a positional `T[]` field of an options struct, which takes
# every value left.
_cli_field_positional<T>(parser: Parser, name: String, help: String, required: bool, current: Array<T>): _CliArgument {
    var declared = parser._declare_positional(name, help, LIST_KIND, required);
    _cli_type<T>(declared);
    return declared;
}

# Stores each declaration's parsed value in its field of `options`, in the
# order `add_options` declared them.
_cli_store<T>(options: T, declared: Array<_CliArgument>) {
    static (options, declared) {
        var index = 0;
        for (var field in reflect.properties<T>()) {
            field.set(options, _cli_field_value(declared[index], field.get(options)));
            index += 1;
        }
    }
}

# What a parse leaves in a `bool` field: whether the flag was given.
_cli_field_value(declared: _CliArgument, current: bool): bool {
    return declared.occurrences > 0;
}

# What a parse leaves in a `T` field: the value given, else the default,
# else an empty String or the field's value.
_cli_field_value<T>(declared: _CliArgument, current: T): T {
    var fallback = current;
    static (fallback) {
        # A String field with no default is emptied, not kept.
        if (reflect.is_same<T, String>()) {
            fallback = "";
        }
    }
    return Argument<T>(declared).value_or(fallback);
}

# What a parse leaves in a `T?` field: the value given, or Empty.
_cli_field_value<T>(declared: _CliArgument, current: T?): T? {
    if (declared.values.is_empty) {
        return Optional<T>.Empty;
    }
    return Optional<T>.Value(Argument<T>(declared).value());
}

# What a parse leaves in a `T[]` field: the values given, in order.
_cli_field_value<T>(declared: _CliArgument, current: Array<T>): Array<T> {
    return ArgumentList<T>(declared).values();
}

# Makes `declared` take values of type `T`: sets what checks them, what an
# error expects, and an enum's choices, and checks its default.
_cli_type<T>(declared: _CliArgument) {
    declared.expected = _cli_expected<T>();
    var any_text = false;
    static (declared, any_text) {
        any_text = reflect.is_same<T, String>();
        declared.names_files = any_text or reflect.is_same<T, Path>();
        if (reflect.is_enum<T>()) {
            for (var case in reflect.cases<T>()) {
                declared.choices.append(_cli_kebab(case.name));
            }
        }
    }
    if (!any_text) {
        declared.check = (text: String) => _cli_convert<T>(text).is_value();
    }
    assert(
        declared.default_value.is_empty or declared.reads(declared.default_value),
        "cli: the default '" + declared.default_value + "' of '" + declared.display() + "' is not " + declared.expected
    );
}

# `text` as a `T`, or Empty when it is not one.
_cli_convert<T>(text: String): T? {
    var out = Optional<T>.Empty;
    static (text, out) {
        if (reflect.is_same<T, String>()) {
            out = Optional<T>.Value(text);
        } else if (reflect.is_same<T, Path>()) {
            out = Optional<T>.Value(Path(text));
        } else if (reflect.is_same<T, byte>()) {
            out = byte.parse(text);
        } else if (reflect.is_same<T, short>()) {
            out = short.parse(text);
        } else if (reflect.is_same<T, ushort>()) {
            out = ushort.parse(text);
        } else if (reflect.is_same<T, int>()) {
            out = int.parse(text);
        } else if (reflect.is_same<T, uint>()) {
            out = uint.parse(text);
        } else if (reflect.is_same<T, long>()) {
            out = long.parse(text);
        } else if (reflect.is_same<T, ulong>()) {
            out = ulong.parse(text);
        } else if (reflect.is_same<T, float>()) {
            out = float.parse(text);
        } else if (reflect.is_same<T, double>()) {
            out = double.parse(text);
        } else if (reflect.is_enum<T>()) {
            for (var case in reflect.cases<T>()) {
                reflect.assert(
                    case.values.is_empty,
                    $"cli cannot read '{reflect.name<T>()}': its case '{case.name}' carries values"
                );
                if (text == _cli_kebab(case.name)) {
                    out = Optional<T>.Value(case.get());
                }
            }
        } else {
            reflect.error(
                $"cli cannot read values of type '{reflect.name<T>()}'; use String, a number type, io.Path or an enum"
            );
        }
    }
    return out;
}

# What an error says a value of type `T` must be: "an integer".
_cli_expected<T>(): String {
    var expected = "a value";
    var names = Array<String>();
    static (expected, names) {
        if (reflect.is_same<T, byte>()) {
            expected = "an integer from 0 to 255";
        } else if (reflect.is_same<T, short>()) {
            expected = "an integer from -32768 to 32767";
        } else if (reflect.is_same<T, ushort>()) {
            expected = "an integer from 0 to 65535";
        } else if (reflect.is_same<T, int>() or reflect.is_same<T, long>()) {
            expected = "an integer";
        } else if (reflect.is_same<T, uint>() or reflect.is_same<T, ulong>()) {
            expected = "a non-negative integer";
        } else if (reflect.is_same<T, float>() or reflect.is_same<T, double>()) {
            expected = "a number";
        } else if (reflect.is_enum<T>()) {
            for (var case in reflect.cases<T>()) {
                names.append(_cli_kebab(case.name));
            }
            expected = _cli_quoted_list(names);
        }
    }
    return expected;
}

# `value` written as on the command line, or empty for an empty String or
# a null.
_cli_text<T>(value: T): String {
    var text = "";
    static (value, text) {
        if (reflect.is_same<T, String>()) {
            text = value === __null ? "" : value;
        } else if (reflect.is_same<T, Path>()) {
            text = value === __null ? "" : value.to_string();
        } else if (reflect.is_enum<T>()) {
            for (var case in reflect.cases<T>()) {
                if (value == case.get()) {
                    text = _cli_kebab(case.name);
                }
            }
        } else {
            text = $"{value}";
        }
    }
    return text;
}

# A case name in kebab case, as the command line writes it: `DebugInfo`
# is `debug-info`.
_cli_kebab(name: String): String {
    var text = StringBuilder();
    ulong index = 0;
    while (index < name.size) {
        var letter = name.substr_bytes(index, 1);
        if (letter != letter.lower() and index > 0) {
            text.append("-");
        }
        text.append(letter.lower());
        index += 1;
    }
    return text.to_string();
}

# The long name of the option for field `field_name`: `name`, or when
# that is empty the field's name with each `_` written `-`.
_cli_long_name(field_name: String, name: String): String {
    return name.is_empty ? field_name.replace("_", "-") : name;
}

# `'a', 'b' or 'c'`.
_cli_quoted_list(names: Array<String>): String {
    var text = StringBuilder();
    ulong index = 0;
    while (index < names.count) {
        if (index > 0) {
            text.append(index + 1 == names.count ? " or " : ", ");
        }
        text.append("'").append(names[index]).append("'");
        index += 1;
    }
    return text.to_string();
}

## An option that takes no value, from `Parser.flag`.
export struct Flag {
    var _argument: _CliArgument = __null;

    ## Wraps a declaration. `Parser.flag` makes flags; this constructor is
    ## for the runtime.
    ##
    ## @param argument the declaration
    construct(argument: _CliArgument) {
        _argument = argument;
    }

    ## Whether the flag was given at least once.
    var is_set: bool {
        get {
            return _argument.occurrences > 0;
        }
    }

    ## How many times the flag was given, so `-vvv` can mean more than `-v`.
    var occurrences: int {
        get {
            return _argument.occurrences;
        }
    }
}

## An option or positional argument that takes one value, from
## `Parser.option` or `Parser.positional`.
##
## @typeParam T the type of the value: `String`, or what `option<T>` or
##   `positional<T>` declared
export struct Argument<T> {
    var _argument: _CliArgument = __null;

    ## Wraps a declaration. `Parser.option` and `Parser.positional` make
    ## arguments; this constructor is for the runtime.
    ##
    ## @param argument the declaration
    construct(argument: _CliArgument) {
        _argument = argument;
    }

    ## Whether a value was given on the command line; false when the
    ## argument was left out, even when it has a default.
    var is_set: bool {
        get {
            return !_argument.values.is_empty;
        }
    }

    ## Returns the value given, or the default when it was left out.
    ##
    ## @returns the value
    ## @panics if the argument was left out and has no default; check
    ##   `is_set` or use `value_or` for an optional argument
    value(): T {
        if (!_argument.values.is_empty) {
            return _cli_convert<T>(_argument.values.last()).value();
        }
        assert(
            !_argument.default_value.is_empty, "cli: '" + _argument.display() + "' was not given and has no default"
        );
        return _cli_convert<T>(_argument.default_value).value();
    }

    ## Returns the value given, or `fallback` when it was left out.
    ##
    ## @param fallback the value to use when the argument was left out
    ## @returns the value given, else the declared default, else `fallback`
    value_or(fallback: T): T {
        if (_argument.values.is_empty and _argument.default_value.is_empty) {
            return fallback;
        }
        return value();
    }
}

## An option that may be given many times, or a positional argument that
## takes every remaining value, from `Parser.multiple` or
## `Parser.positionals`.
##
## @typeParam T the type of each value: `String`, or what `multiple<T>`
##   or `positionals<T>` declared
export struct ArgumentList<T> {
    var _argument: _CliArgument = __null;

    ## Wraps a declaration. `Parser.multiple` and `Parser.positionals` make
    ## argument lists; this constructor is for the runtime.
    ##
    ## @param argument the declaration
    construct(argument: _CliArgument) {
        _argument = argument;
    }

    ## Whether at least one value was given.
    var is_set: bool {
        get {
            return !_argument.values.is_empty;
        }
    }

    ## Returns the values given, in command-line order.
    ##
    ## @returns a new array of the values, empty when none was given
    values(): Array<T> {
        var values = Array<T>(_argument.values.count);
        for (var text in _argument.values) {
            values.append(_cli_convert<T>(text).value());
        }
        return values;
    }
}
