# Readable names for recorded frames: Pepper's linker names demangled, and,
# with llvm-symbolizer, the functions inlined at each address, with their
# files and lines, read from the program's debug info.

import json;
import os;
import process;

# Every printable ASCII character, from space (32) on: the bytes a Pepper
# linker name escapes as `_` and two hex digits.
const PRINTABLE = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";

# How many addresses one llvm-symbolizer run takes on its command line,
# which stays well under Windows' 32 KB limit.
const SYMBOLIZER_BATCH = 400;

# The readable name of a symbol. A Pepper linker name (`_P` and the name
# with `_` doubled and other bytes as `_xx`, see `symbol_name` in
# pepper-codegen's partition.rs) is decoded, then its file namespaces
# (`helper@io/file`) and overload numbers (`f$2`) are dropped:
# `_PArray_3cint_3e.count` is `Array<int>.count`. A closure's body,
# `__closure_3@main.__call`, is `closure #3 in main`. Any other name is
# returned as it is.
export demangle(symbol: String): String {
    if (!symbol.starts_with("_P") or symbol.size < 3) {
        return symbol;
    }
    var decoded = decode(symbol);
    if (decoded.is_empty()) {
        return symbol;
    }
    var name = decoded.value();
    if (name.starts_with("__closure_") and name.ends_with(".__call")) {
        var inner = name.substr_bytes(10, name.size - 10 - 7);
        var parts = inner.split_once("@");
        if (parts.is_value()) {
            var (number, namespace) = parts.value();
            return $"closure #{number} in {namespace}";
        }
        return $"closure #{inner}";
    }
    return drop_suffixes(name);
}

# The name a `_P` linker name spells, or none when it is not one.
decode(symbol: String): String? {
    var out = StringBuilder();
    ulong start = 2;
    ulong index = 2;
    while (index < symbol.size) {
        if (symbol.byte_at(index) != '_') {
            index += 1;
            continue;
        }
        out.append(symbol.substr_bytes(start, index - start));
        if (index + 1 < symbol.size and symbol.byte_at(index + 1) == '_') {
            out.append("_");
            index += 2;
        } else if (index + 2 < symbol.size) {
            var high = symbol.byte_at(index + 1).digit_value(16);
            var low = symbol.byte_at(index + 2).digit_value(16);
            if (high.is_empty() or low.is_empty()) {
                return Optional<String>.Empty;
            }
            var code = high.value() * 16 + low.value();
            if (code < 32 or code > 126) {
                return Optional<String>.Empty;
            }
            out.append(PRINTABLE.substr_bytes((code - 32) as ulong, 1));
            index += 3;
        } else {
            return Optional<String>.Empty;
        }
        start = index;
    }
    out.append(symbol.substr_bytes(start, symbol.size - start));
    return Optional<String>.Value(out.to_string());
}

# `name` without each `@namespace` and `$overload` part, each of which runs
# to the next `.`, `<`, `>`, `,` or space.
drop_suffixes(name: String): String {
    if (name.find("@") < 0 and name.find("$") < 0) {
        return name;
    }
    var out = StringBuilder();
    ulong start = 0;
    ulong index = 0;
    var skipping = false;
    while (index < name.size) {
        var c = name.byte_at(index);
        if (!skipping and (c == '@' or c == '$')) {
            out.append(name.substr_bytes(start, index - start));
            skipping = true;
        } else if (skipping and (c == '.' or c == '<' or c == '>' or c == ',' or c == ' ')) {
            skipping = false;
            start = index;
        }
        index += 1;
    }
    if (!skipping) {
        out.append(name.substr_bytes(start, name.size - start));
    }
    return out.to_string();
}

# One function at an address: the function itself, or one inlined into it.
export struct Location {
    var function: String;
    var file: String;
    var line: long;

    construct(function: String, file: String, line: long) {
        this.function = function;
        this.file = file;
        this.line = line;
    }
}

# Runs llvm-symbolizer over a library's addresses.
export struct Symbolizer {
    var program: String;

    construct(program: String) {
        this.program = program;
    }

    # The functions at each of `addresses` in `library`, innermost (the
    # one the address is in) first, then each it is inlined into; an empty
    # list for an address the debug info does not cover. With `relative`,
    # the addresses count from the library's image base
    # (`--relative-address`), as samply records them.
    locations(library: String, addresses: Array<ulong>, relative: bool): Array<Array<Location>> {
        var found = Array<Array<Location>>();
        ulong next = 0;
        while (next < addresses.count) {
            var arguments = Array<String>();
            arguments.append("--obj=" + library);
            arguments.append("--output-style=JSON");
            arguments.append("--inlines");
            # The debug info's names (`Box<int>.get`, `closure at main.pep:3`)
            # rather than the symbol table's linker names.
            arguments.append("--functions=short");
            if (relative) {
                arguments.append("--relative-address");
            }
            var end = next + SYMBOLIZER_BATCH < addresses.count ? next + SYMBOLIZER_BATCH : addresses.count;
            for (var index in next..end) {
                arguments.append(to_string(addresses[index]));
            }
            var answers = run(arguments);
            for (var index in next..end) {
                var answer = answers.count > index - next ? answers[index - next] : json.JsonValue.Null;
                found.append(locations_of(answer["Symbol"]));
            }
            next = end;
        }
        return found;
    }

    # The address of each symbol of `names` in `library`, or 0 for one the
    # library does not define.
    starts(library: String, names: Array<String>): Array<ulong> {
        var found = Array<ulong>();
        ulong next = 0;
        while (next < names.count) {
            var arguments = Array<String>();
            arguments.append("--obj=" + library);
            arguments.append("--output-style=JSON");
            var end = next + SYMBOLIZER_BATCH < names.count ? next + SYMBOLIZER_BATCH : names.count;
            for (var index in next..end) {
                arguments.append(names[index]);
            }
            var answers = run(arguments);
            for (var index in next..end) {
                ulong start = 0;
                if (answers.count > index - next) {
                    var text = answers[index - next]["Loc"][0]["StartAddress"].as_string();
                    if (text.is_value() and text.value().starts_with("0x")) {
                        var parsed = ulong.parse(text.value().substr_bytes(2, text.value().size - 2), 16);
                        if (parsed.is_value()) {
                            start = parsed.value();
                        }
                    }
                }
                found.append(start);
            }
            next = end;
        }
        return found;
    }

    # llvm-symbolizer's answers to `arguments`, one per input, or none when
    # it fails.
    run(arguments: Array<String>): Array<json.JsonValue> {
        var ran = process.Command(program).arguments(arguments).run();
        if (ran.is_err() or !ran.value().status.success()) {
            return Array<json.JsonValue>();
        }
        var parsed = json.parse(ran.value().stdout);
        if (parsed.is_err()) {
            return Array<json.JsonValue>();
        }
        var answers = parsed.value().as_array();
        return answers.is_value() ? answers.value() : Array<json.JsonValue>();
    }
}

# The locations in one llvm-symbolizer answer's `Symbol` list.
locations_of(symbols: json.JsonValue): Array<Location> {
    var found = Array<Location>();
    var list = symbols.as_array();
    if (list.is_empty()) {
        return found;
    }
    for (var symbol in list.value()) {
        var function = symbol["FunctionName"].as_string();
        if (function.is_empty() or function.value() == "??" or function.value().is_empty) {
            continue;
        }
        var file = symbol["FileName"].as_string();
        var line = symbol["Line"].as_int();
        found.append(
            Location(
                demangle(function.value()), file.is_value() ? file.value() : "", line.is_value() ? line.value() : 0
            )
        );
    }
    return found;
}

# The llvm-symbolizer to use: `requested` when given, else the first found
# on the PATH (`llvm-symbolizer`, then a versioned one such as
# `llvm-symbolizer-20`), in `$LLVM_SYS_<major>1_PREFIX/bin`, or in the
# usual LLVM install directories. None when there is none.
export find_symbolizer(requested: String): String? {
    if (!requested.is_empty) {
        var given = process.find_executable(requested);
        return given.is_value() ? Optional<String>.Value(given.value().to_string()) : Optional<String>.Empty;
    }
    var names = Array<String>();
    names.append("llvm-symbolizer");
    for (var major in 14..>30) {
        names.append($"llvm-symbolizer-{44 - major}");
    }
    for (var name in names) {
        var found = process.find_executable(name);
        if (found.is_value()) {
            return Optional<String>.Value(found.value().to_string());
        }
    }
    var directories = Array<String>();
    for (var major in 14..>30) {
        var prefix = os.environment($"LLVM_SYS_{44 - major}1_PREFIX");
        if (prefix.is_value()) {
            directories.append(prefix.value() + "/bin");
        }
    }
    directories.append("/opt/homebrew/opt/llvm/bin");
    directories.append("/usr/local/opt/llvm/bin");
    directories.append("C:\\Program Files\\LLVM\\bin");
    for (var directory in directories) {
        var found = process.find_executable(directory + "/llvm-symbolizer");
        if (found.is_value()) {
            return Optional<String>.Value(found.value().to_string());
        }
    }
    return Optional<String>.Empty;
}
