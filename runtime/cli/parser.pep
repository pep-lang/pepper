## Parser and the handles its declarations return: Flag, Argument and
## ArgumentList.

import [File] from io;
import process;

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
    var default_value: String = "";
    var values: Array<String> = __null;
    var occurrences: int = 0;

    construct(name: String, short_name: String, help: String, kind: int, positional: bool) {
        this.name = name;
        this.short_name = short_name;
        this.help = help;
        this.kind = kind;
        this.positional = positional;
        values = Array<String>();
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
    }

    ## Declares an option that takes no value, such as `--verbose`.
    ##
    ## @param name the long name, without `--`
    ## @param short_name the one-letter short name, without `-`, or empty for none
    ## @param help what the option does, for the help
    ## @returns the handle that tells whether the flag was given
    ## @panics if `name` or `short_name` is invalid or already declared
    flag(name: String, short_name: String = "", help: String = ""): Flag {
        return Flag(_declare_option(name, short_name, help, FLAG_KIND));
    }

    ## Declares an option that takes one value, such as `--output a.out`.
    ##
    ## @param name the long name, without `--`
    ## @param short_name the one-letter short name, without `-`, or empty for none
    ## @param help what the option sets, for the help
    ## @param value_name what the help calls the value; empty for the long
    ##   name in capitals (`OUTPUT`)
    ## @param default_value the value when the option is not given; empty for none
    ## @param required whether leaving the option out is an error
    ## @returns the handle that reads the value
    ## @panics if `name` or `short_name` is invalid or already declared
    option(
        name: String,
        short_name: String = "",
        help: String = "",
        value_name: String = "",
        default_value: String = "",
        required: bool = false
    ): Argument {
        var declared = _declare_option(name, short_name, help, SINGLE_KIND);
        declared.value_name = value_name.is_empty ? name.upper().replace("-", "_") : value_name;
        declared.default_value = default_value;
        declared.required = required;
        return Argument(declared);
    }

    ## Declares an option that may be given any number of times, each with a
    ## value, such as `-I src -I lib`.
    ##
    ## @param name the long name, without `--`
    ## @param short_name the one-letter short name, without `-`, or empty for none
    ## @param help what the option adds, for the help
    ## @param value_name what the help calls the value; empty for the long
    ##   name in capitals (`IMPORT_PATH`)
    ## @param required whether leaving the option out is an error
    ## @returns the handle that reads the values, in the order given
    ## @panics if `name` or `short_name` is invalid or already declared
    multiple(
        name: String, short_name: String = "", help: String = "", value_name: String = "", required: bool = false
    ): ArgumentList {
        var declared = _declare_option(name, short_name, help, LIST_KIND);
        declared.value_name = value_name.is_empty ? name.upper().replace("-", "_") : value_name;
        declared.required = required;
        return ArgumentList(declared);
    }

    ## Declares the next positional argument. Positional arguments are
    ## filled in the order they are declared.
    ##
    ## @param name what the help and errors call it
    ## @param help what it is, for the help
    ## @param required whether leaving it out is an error
    ## @param default_value the value when it is left out; empty for none
    ## @returns the handle that reads the value
    ## @panics if `name` is empty or already declared, if a required argument
    ##   follows an optional one, if it follows `positionals`, or if the
    ##   parser has commands
    positional(name: String, help: String = "", required: bool = true, default_value: String = ""): Argument {
        var declared = _declare_positional(name, help, SINGLE_KIND, required);
        declared.default_value = default_value;
        return Argument(declared);
    }

    ## Declares a positional argument that takes every remaining value, such
    ## as a list of files. It must be the last positional argument.
    ##
    ## @param name what the help and errors call it
    ## @param help what the values are, for the help
    ## @param required whether at least one value must be given
    ## @returns the handle that reads the values, in the order given
    ## @panics if `name` is empty or already declared, if it follows
    ##   `positionals`, or if the parser has commands
    positionals(name: String, help: String = "", required: bool = false): ArgumentList {
        return ArgumentList(_declare_positional(name, help, LIST_KIND, required));
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
        _commands.append(command);
        return command;
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
        labels.append(_find_short("h") === __null ? "-h, --help" : "    --help");
        descriptions.append("show this help");
        if (!_version.is_empty) {
            labels.append(_find_short("V") === __null ? "-V, --version" : "    --version");
            descriptions.append("show the version");
        }
        _append_section(text, "Options", labels, descriptions);
        return text.to_string();
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
        return _parse(args, 1, this);
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

    _find_option(name: String): _CliArgument {
        for (var option in _options) {
            if (option.name == name) {
                return option;
            }
        }
        return __null;
    }

    _find_short(short_name: String): _CliArgument {
        for (var option in _options) {
            if (option.short_name == short_name) {
                return option;
            }
        }
        return __null;
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
                } else if (attached) {
                    _store(option, attached.value());
                } else if (index < args.count) {
                    _store(option, args[index]);
                    index += 1;
                } else {
                    return _fail(root, "missing value for '--" + name + "'");
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
                    var rest = argument.substr_bytes(at, argument.size - at);
                    if (rest.starts_with("=")) {
                        rest = rest.substr_bytes(1, rest.size - 1);
                        _store(option, rest);
                    } else if (!rest.is_empty) {
                        _store(option, rest);
                    } else if (index < args.count) {
                        _store(option, args[index]);
                        index += 1;
                    } else {
                        return _fail(root, "missing value for '-" + letter + "'");
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
                positional.values.append(argument);
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

    # An error for each required option left out.
    _check_required(root: Parser): Result<String?> {
        for (var option in _options) {
            if (option.required and option.values.is_empty) {
                return _fail(root, "missing required option '--" + option.name + "'");
            }
        }
        return Result<String?>.ok(Optional<String>.Empty);
    }

    # A value for `option`: the last one wins unless it is repeatable.
    _store(option: _CliArgument, value: String) {
        if (option.kind == SINGLE_KIND) {
            option.values.clear();
        }
        option.values.append(value);
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
        var text = "";
        ulong index = 0;
        while (index < _commands.count) {
            if (index > 0) {
                text = text + (index + 1 == _commands.count ? " or " : ", ");
            }
            text = text + "'" + _commands[index]._name + "'";
            index += 1;
        }
        return text;
    }

    # "unknown option '--outptu'; did you mean '--output'?"
    _unknown_option(name: String): String {
        var message = "unknown option '--" + name + "'";
        var names = Array<String>();
        for (var option in _options) {
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
export struct Argument {
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
    value(): String {
        if (!_argument.values.is_empty) {
            return _argument.values.last();
        }
        assert(
            !_argument.default_value.is_empty, "cli: '" + _argument.display() + "' was not given and has no default"
        );
        return _argument.default_value;
    }

    ## Returns the value given, or `fallback` when it was left out.
    ##
    ## @param fallback the value to use when the argument was left out
    ## @returns the value given, else the declared default, else `fallback`
    value_or(fallback: String): String {
        if (!_argument.values.is_empty) {
            return _argument.values.last();
        }
        if (!_argument.default_value.is_empty) {
            return _argument.default_value;
        }
        return fallback;
    }
}

## An option that may be given many times, or a positional argument that
## takes every remaining value, from `Parser.multiple` or
## `Parser.positionals`.
export struct ArgumentList {
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
    values(): Array<String> {
        return _argument.values.clone();
    }
}
