# The compiler's parser parses every source file in the repository. Until
# the self-hosting cutover it was held to build the same syntax tree as the Rust
# parser; the curated programs of link_test, sema_test and passes_test
# now hold the compiler to its diagnostics.

import [parse_type_text, Span] from compiler.ast;
import io;
import [Directory, File, Path] from io;
import compiler.parse;

# The files are split in parts, each a test of its own, so they run side
# by side.
[Test]
parses_every_source_file_part_1() {
    parses_sources(0);
}

[Test]
parses_every_source_file_part_2() {
    parses_sources(1);
}

[Test]
parses_every_source_file_part_3() {
    parses_sources(2);
}

[Test]
parses_every_source_file_part_4() {
    parses_sources(3);
}

[Test]
parses_every_source_file_part_5() {
    parses_sources(4);
}

[Test]
parses_every_source_file_part_6() {
    parses_sources(5);
}

[Test]
parses_every_source_file_part_7() {
    parses_sources(6);
}

[Test]
parses_every_source_file_part_8() {
    parses_sources(7);
}

# The return type of `source`'s first function, as text and its span's end.
return_type_of(source: String): (String, ulong) {
    var module = parse.parse(source);
    if (module.is_err()) {
        return (module.error().message, 0 as ulong);
    }
    if (module.value().declarations[0] is Function(function)) {
        return (function.return_type.to_string(), function.return_type.span.end);
    }
    return ("", 0 as ulong);
}

[Test]
parses_array_and_optional_suffixes_after_a_tuple_type() {
    expect_equal(return_type_of("f(): (String, int)[] {}"), ("(String, int)[]", 20 as ulong));
    expect_equal(return_type_of("f(): (a: int, b: int)[][] {}"), ("(a: int, b: int)[][]", 25 as ulong));
    expect_equal(return_type_of("f(): (int, int)[]? {}"), ("Optional<(int, int)[]>", 18 as ulong));
    expect_equal(return_type_of("f(): Box<int>[] {}"), ("Box<int>[]", 15 as ulong));
}

# `parse_type_text` reads back each type as the parser spells it, as a
# generic method's type arguments are kept (pepper#149), and stops on text
# no spelling makes.
[Test]
reads_back_a_type_as_the_parser_spells_it() {
    for (var written in [
        "Box<(a: int, b: int)>",
        "(int, String)[]",
        "Box<int>[]",
        "HashMap<String, (int) => bool>",
        "shared (int, int) => (x: int, y: int)",
        "extern () => int",
        "Optional<(int, int)[]>",
        "__ptr<int>"
    ]) {
        var (spelled, _) = return_type_of("f(): " + written + " {}");
        expect_equal(parse_type_text(spelled, Span()).to_string(), spelled);
    }
    expect_true(parse_type_text("a<b c>", Span()).to_string() != "a<b c>");
}

# Each statement of `source`'s first function: the type and name a local
# declaration writes (`type name`), else `expression`.
statements_of(source: String): String[] {
    var out = Array<String>();
    var module = parse.parse(source);
    if (module.is_err()) {
        out.append(module.error().message);
        return out;
    }
    if (module.value().declarations[0] is Function(function)) {
        for (var statement in function.body.value().statements) {
            var shown = "other";
            if (statement is Expression(_)) {
                shown = "expression";
            } else if (statement is Declaration(local)) {
                if (local is Variable(variable)) {
                    shown = $"{variable.type_name.to_string()} {variable.name}";
                }
            }
            out.append(shown);
        }
    }
    return out;
}

# A local declaration may start with a tuple type (pepper#130), and a
# statement starting with `(` that declares nothing stays an expression.
[Test]
parses_a_local_declaration_that_starts_with_a_tuple_type() {
    var source = "f() {\n"
        + "    (String, int)[] a = [];\n"
        + "    (int, String)? b;\n"
        + "    (line: int, column: int) c = (1, 2);\n"
        + "    (int) => int d = g;\n"
        + "    (a, b) = (b, a);\n"
        + "    (g)(x);\n"
        + "    (x);\n"
        + "}\n";
    expect_equal(
        "; ".join(statements_of(source)),
        "(String, int)[] a; Optional<(int, String)> b; (line: int, column: int) c; (int) => int d; "
            + "expression; expression; expression"
    );
}

const PARSE_PARTS: ulong = 8;

# Checks every `PARSE_PARTS`th source file of the repository, from the `part`th.
parses_sources(part: ulong) {
    var files = Array<Path>();
    # The folders, from the repository's root, whose `.pep` files are
    # checked.
    for (var folder in ["runtime", "tools", "tests", "docs/examples"]) {
        collect_sources(Path("..").join(folder), files);
    }
    expect_true(files.count > 400, "the repository's sources are found from tools/");
    ulong failed = 0;
    var i = part;
    while (i < files.count) {
        if (!parses(files[i])) {
            failed += 1;
        }
        i += PARSE_PARTS;
    }
    expect_equal(failed, 0 as ulong);
}

# Whether `file` parses, reporting why when it does not.
parses(file: Path): bool {
    var source = File.read_to_string(file);
    if (source.is_err()) {
        print($"{file}: cannot read it");
        return false;
    }
    var module = parse.parse(source.value());
    if (module.is_err()) {
        var error = module.error();
        print($"{file}:{error.span.start}: {error.message}");
        return false;
    }
    return true;
}

# Appends the `.pep` files under `folder` to `out`, in name order, leaving
# out build folders.
collect_sources(folder: Path, out: Path[]) {
    var listing = Directory.open(folder);
    if (listing.is_err()) {
        return;
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return;
    }
    var names = Array<String>();
    var by_name = HashMap<String, io.DirEntry>();
    for (var entry in entries.value()) {
        names.append(entry.name);
        by_name[entry.name] = entry;
    }
    names.sort((a, b) => a.compare(b));
    for (var name in names) {
        var entry = by_name[name];
        if (entry.is_directory and !name.starts_with(".")) {
            collect_sources(entry.path, out);
        } else if (entry.is_file and name.ends_with(".pep")) {
            out.append(entry.path);
        }
    }
}
