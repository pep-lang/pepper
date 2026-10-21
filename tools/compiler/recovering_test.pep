# `parse.parse_recovering` reads on past syntax errors: on every source
# file of the repository, intact and broken the three ways step 1 of the self-hosting cutover
# measured (the last `}` removed, a `;` in the second half removed, the
# rest of a line after ` = ` in the second half removed), it returns, and
# its first error is the one `parse` reports. Hand-written cases check the
# partial module and the errors after the first.

import io;
import [Directory, File, Path] from io;
import compiler.parse;
import [ParseError, Recovered] from compiler.parse;

[Test]
recovers_from_broken_versions_of_every_source_file() {
    var files = Array<Path>();
    for (var folder in ["runtime", "tools", "tests", "docs/examples"]) {
        collect_sources(Path("..").join(folder), files);
    }
    expect_true(files.count > 400, "the repository's sources are found from tools/");
    ulong broken = 0;
    ulong first_differs = 0;
    ulong declarations_lost = 0;
    ulong valid_differs = 0;
    for (var file in files) {
        var source = File.read_to_string(file);
        if (source.is_err()) {
            continue;
        }
        var intact = source.value();
        var whole = parse.parse(intact);
        var recovered = parse.parse_recovering(intact);
        if (whole.is_ok()) {
            if (recovered.errors.count > 0 or recovered.module.declarations.count != whole.value().declarations.count) {
                print($"{file}: parses, but not to the same module with no errors");
                valid_differs += 1;
            }
        }
        for (var kind in ["unclosed", "semicolon", "unfinished"]) {
            var text = broken_version(intact, kind);
            var parsed = parse.parse(text);
            if (parsed.is_ok()) {
                continue;
            }
            broken += 1;
            var result = parse.parse_recovering(text);
            if (!same_error(result.errors[0], parsed.error())) {
                print($"{file} ({kind}): the first error is not parse's");
                first_differs += 1;
            }
            # A missing last `}` costs no declaration.
            if (kind == "unclosed" and whole.is_ok()) {
                if (result.module.declarations.count != whole.value().declarations.count) {
                    print($"{file} ({kind}): declarations lost");
                    declarations_lost += 1;
                }
            }
        }
    }
    expect_true(broken > 1000, "most broken versions do not parse");
    expect_equal(valid_differs, 0 as ulong);
    expect_equal(first_differs, 0 as ulong);
    expect_equal(declarations_lost, 0 as ulong);
}

[Test]
gives_a_valid_source_its_module_and_no_errors() {
    var source = "import io;\n\nf(x: int): int {\n    return x + 1;\n}\n";
    var recovered = parse.parse_recovering(source);
    expect_equal(recovered.errors.count, 0 as ulong);
    expect_equal(recovered.module.to_json().to_string(), parse.parse(source).value().to_json().to_string());
}

[Test]
reports_each_broken_statement_and_keeps_the_rest() {
    var source = "f(): int {\n    var a = 1\n    var b = ;\n    var c = 3;\n    return a +;\n}\n\ng() {}\n";
    var recovered = parse.parse_recovering(source);
    expect_errors(recovered, ["expected ';'", "expected expression", "expected expression"]);
    # `var a` (its `;` is missing) and `var c` are kept; `var b` and the
    # `return` are not.
    expect_equal(recovered.module.declarations.count, 2 as ulong);
    expect_equal(function_body_count(recovered, 0), 2 as ulong);
}

[Test]
reports_a_missing_last_brace_at_the_end_with_its_brace() {
    var source = "f() {\n    if (true) {\n        g();\n    }\n";
    var recovered = parse.parse_recovering(source);
    expect_errors(recovered, ["expected '}'"]);
    var error = recovered.errors[0];
    expect_equal(error.span.start, source.size);
    expect_equal(error.related.value().start, 4 as ulong);
    expect_equal(error.related_message, "to match this '{'");
    expect_equal(recovered.module.declarations.count, 1 as ulong);
}

[Test]
names_the_inner_brace_that_lost_its_closing_brace() {
    # The `if`'s `}` is missing, so it takes `f`'s, at a lesser indentation.
    var source = "f() {\n    if (true) {\n        g();\n}\n";
    var recovered = parse.parse_recovering(source);
    expect_errors(recovered, ["expected '}'"]);
    expect_equal(recovered.errors[0].related.value().start, 20 as ulong);
}

[Test]
closes_a_body_before_a_line_no_deeper_than_its_brace() {
    var source = "g() {\n    print(\"hi\");\n\nh(): int {\n    return 2;\n}\n";
    var recovered = parse.parse_recovering(source);
    expect_errors(recovered, ["expected ';'", "expected '}'"]);
    var unclosed = recovered.errors[1];
    expect_equal(unclosed.span.start, source.find("h()") as ulong);
    expect_equal(unclosed.related.value().start, 4 as ulong);
    # Both functions are kept.
    expect_equal(recovered.module.declarations.count, 2 as ulong);
}

[Test]
recovers_inside_structs_and_enums() {
    var source = "struct S {\n    var x: int\n    var y: int;\n    m() {\n        return +;\n    }\n}\n\n"
        + "enum E {\n    A,\n    B;\n\n    n(): int {\n        return 1 +;\n    }\n}\n";
    var recovered = parse.parse_recovering(source);
    expect_errors(recovered, ["expected ';'", "expected expression", "expected expression"]);
    expect_equal(recovered.module.declarations.count, 2 as ulong);
}

[Test]
reads_a_line_the_lexer_refuses_as_spaces() {
    var source = "f() {\n    var s = \"open;\n    var t = ;\n}\n";
    var recovered = parse.parse_recovering(source);
    expect_equal(recovered.errors[0].message, parse.parse(source).error().message);
    expect_errors(recovered, [recovered.errors[0].message, "expected expression", "expected expression"]);
    expect_equal(recovered.module.declarations.count, 1 as ulong);
}

# A `\x` with fewer than two hex digits before the closing quote is an
# error at the escape, not a panic (#67).
[Test]
reports_a_hex_escape_cut_short() {
    for (var literal in ["\"\\x\"", "\"\\x4\"", "\"a\\x\"", "$\"\\x\"", "'\\x'", "'\\x4'", "\"\\xG1\""]) {
        var source = "f() { var s = " + literal + "; }";
        var parsed = parse.parse(source);
        if (parsed.is_ok()) {
            panic(literal + " parses");
        }
        expect_equal(parsed.error().message, "expected two hex digits after '\\x'");
        expect_equal(source.byte_at(parsed.error().span.start), '\\');
    }
    expect_true(parse.parse("f() { var s = \"\\x41\"; var c = '\\x41'; }").is_ok(), "two hex digits parse");
}

[Test]
skips_a_broken_declaration_with_its_body() {
    var source = "f(x: int = ) {\n    return;\n}\n\ng() {}\n";
    var recovered = parse.parse_recovering(source);
    expect_equal(recovered.errors.count, 1 as ulong);
    expect_equal(recovered.module.declarations.count, 1 as ulong);
}

[Test]
stops_at_a_hundred_errors() {
    var source = StringBuilder();
    source.append("f() {\n");
    for (var i in 0..300) {
        source.append("    var x = ;\n");
    }
    source.append("}\n");
    var recovered = parse.parse_recovering(source.to_string());
    expect_equal(recovered.errors.count, 100 as ulong);
}

# Expects the messages of `recovered`'s errors to be `messages`, in order.
expect_errors(recovered: Recovered, messages: String[]) {
    var actual = Array<String>();
    for (var error in recovered.errors) {
        actual.append(error.message);
    }
    if (actual != messages) {
        var found = Array<String>();
        for (var error in recovered.errors) {
            found.append($"{error.span.start}: {error.message}");
        }
        print("errors: " + ", ".join(found));
    }
    expect_equal(", ".join(actual), ", ".join(messages));
}

# The number of statements in the body of the function that is
# declaration `index`.
function_body_count(recovered: Recovered, index: ulong): ulong {
    var declaration = recovered.module.declarations[index];
    if (declaration is Function(decl)) {
        return decl.body.value().statements.count;
    }
    return 0;
}

# Whether two errors have the same message and span.
same_error(a: ParseError, b: ParseError): bool {
    return a.message == b.message and a.span.start == b.span.start and a.span.end == b.span.end;
}

# `source` broken one of step 1's ways.
broken_version(source: String, kind: String): String {
    if (kind == "unclosed") {
        var i = source.rfind("}");
        return i < 0 ? source : cut(source, i as ulong, i as ulong + 1);
    }
    if (kind == "semicolon") {
        var i = source.find(";", source.size / 2);
        return i < 0 ? source : cut(source, i as ulong, i as ulong + 1);
    }
    var at = source.find(" = ", source.size / 2);
    if (at < 0) {
        return source;
    }
    var start = at as ulong + 3;
    var line_end = source.find("\n", start);
    return line_end < 0 ? source.substr_bytes(0, start) : cut(source, start, line_end as ulong);
}

# `source` without bytes `start` to `end`.
cut(source: String, start: ulong, end: ulong): String {
    return source.substr_bytes(0, start) + source.substr_bytes(end, source.size - end);
}

# Appends the `.pep` files under `folder` to `out`, leaving out build
# folders.
collect_sources(folder: Path, out: Path[]) {
    var listing = Directory.open(folder);
    if (listing.is_err()) {
        return;
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return;
    }
    for (var entry in entries.value()) {
        if (entry.is_directory and !entry.name.starts_with(".")) {
            collect_sources(entry.path, out);
        } else if (entry.is_file and entry.name.ends_with(".pep")) {
            out.append(entry.path);
        }
    }
}
