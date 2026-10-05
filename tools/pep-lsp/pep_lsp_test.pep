# pep-lsp's tests: the outline, analysis of documents on disk, and hover
# and go-to-definition.

import [Directory, File, Path] from io;
import lsp;
import compiler.parse;
import "analysis";
import "navigate";
import "symbols";

# Writes `text` to `name` in a new temporary folder; returns its URI.
temp_file(name: String, text: String): String {
    return temp_file_in(name, name, text);
}

# Writes `text` to `name` in the temporary folder `temp_file(folder, ...)`
# writes to; returns its URI.
temp_file_in(folder: String, name: String, text: String): String {
    var path = Directory.temp().join(Path($"pep-lsp-test-{folder}"));
    Directory.create_all(path);
    path = path.join(Path(name));
    File.write_text(path, text);
    return lsp.path_to_uri(path.to_string());
}

[Test]
outlines_declarations_and_struct_members() {
    var text = "struct Point {\n    var x: int;\n    length(): float { return 0.0; }\n}\n"
        + "enum Color { Red, Green }\n"
        + "area<T: Shape>(shape: T, scale: int = 1): long { return 0; }\n"
        + "var count = 3;\n";
    var document = lsp.TextDocument("file:///a.pep", text);
    var symbols = document_symbols(document, parse.parse(text).value());
    expect_equal(symbols.count, 4 as ulong);
    expect_equal(symbols[0].name, "Point");
    expect_equal(symbols[0].kind, lsp.SYMBOL_STRUCT);
    expect_equal(symbols[0].children[0].name, "x");
    expect_equal(symbols[0].children[0].detail.value(), "int");
    expect_equal(symbols[0].children[1].detail.value(), "length(): float");
    expect_equal(symbols[0].children[1].kind, lsp.SYMBOL_METHOD);
    expect_equal(symbols[1].kind, lsp.SYMBOL_ENUM);
    expect_equal(symbols[1].children[1].detail.value(), "Color.Green");
    expect_equal(symbols[2].detail.value(), "area<T: Shape>(shape: T, scale: int): long");
    expect_equal(symbols[2].selection_range.start.line, 5);
    expect_equal(symbols[3].detail.value(), "int");
}

[Test]
reports_a_syntax_error_without_loading_the_program() {
    var analysis = analyze("file:///nowhere/a.pep", "main(): int {\n    return 0\n}\n");
    expect_equal(analysis.outcome, "did not parse");
    expect_equal(analysis.diagnostics.count, 1 as ulong);
    expect_equal(analysis.diagnostics[0].message, "expected ';'");
    expect_equal(analysis.diagnostics[0].range.start.line, 1);
    expect_equal(analysis.diagnostics[0].range.start.character, 12);
}

[Test]
reports_the_first_type_error_of_the_text_given() {
    # The file on disk is fine; the editor's text is not.
    var uri = temp_file("typed.pep", "main(): int {\n    return 0;\n}\n");
    var analysis = analyze(uri, "main(): int {\n    return \"x\";\n}\n");
    expect_equal(analysis.outcome, "found an error");
    expect_equal(analysis.diagnostics.count, 1 as ulong);
    var error = analysis.diagnostics[0];
    expect_equal(error.message, "cannot return a value of type 'String' from 'main', which returns 'int'");
    expect_equal(error.severity.value(), lsp.SEVERITY_ERROR);
    expect_equal(error.range.start.line, 1);
    expect_true(analysis.files > 1);

    var passed = analyze(uri, "main(): int {\n    return 0;\n}\n");
    expect_equal(passed.outcome, "passed");
    expect_equal(passed.diagnostics.count, 0 as ulong);
}

[Test]
warns_about_an_import_it_cannot_find() {
    var uri = temp_file("imports.pep", "");
    var analysis = analyze(uri, "import nowhere_to_be_found;\nmain(): int {\n    return 0;\n}\n");
    expect_true(analysis.diagnostics.count > 0);
    expect_equal(analysis.diagnostics[0].severity.value(), lsp.SEVERITY_WARNING);
    expect_equal(analysis.diagnostics[0].range.start.line, 0);
}

# Analyzes `text` as the document `uri` and gives the context hover and
# definition read, with the analysis's program and model.
analyzed(uri: String, text: String): Context {
    var analysis = analyze(uri, text);
    expect_equal(analysis.outcome, "passed");
    var context = Context(lsp.TextDocument(uri, text), parse.parse(text).value());
    context.program = analysis.program;
    context.model = analysis.model;
    context.state = analysis.state;
    return context;
}

# The byte offset of the first `needle` in `text`, plus `delta`.
at(text: String, needle: String, delta: ulong): ulong {
    var found = text.find(needle);
    expect_true(found >= 0);
    return found as ulong + delta;
}

# The hover's text at `offset`; empty when there is none.
hover_text(context: Context, offset: ulong): String {
    var hover = hover_at(context, offset);
    if (hover.is_empty()) {
        return "";
    }
    return hover.value().contents.value;
}

# The text where the first definition at `offset` starts, to the end of
# its line, and the file's name; empty when there is none.
definition_text(context: Context, offset: ulong): String {
    var locations = definition_at(context, offset);
    if (locations.count == 0) {
        return "";
    }
    var location = locations[0];
    var path = Path(lsp.uri_to_path(location.uri).value());
    var source = location.uri == context.document.uri ? context.document.text : File.read_to_string(path).value();
    var start = lsp.TextDocument(location.uri, source).offset_at(location.range.start);
    var end = source.find("\n", start);
    var line = source.substr_bytes(start, (end < 0 ? source.size : end as ulong) - start);
    return $"{path.file_name().value()}: {line}";
}

[Test]
hover_and_definition_follow_an_import() {
    temp_file(
        "imported.pep", "## Doubles `x`.\n##\n## @param x the value\nexport twice(x: int): int { return x * 2; }\n"
    );
    var text = "import \"imported\";\nmain(): int {\n    return twice(1);\n}\n";
    var context = analyzed(temp_file_in("imported.pep", "main.pep", text), text);
    var hover = hover_text(context, at(text, "twice(1)", 1));
    expect_true(hover.contains("`twice(x: int): int`"));
    expect_true(hover.contains("imported.pep"));
    expect_true(hover.contains("Doubles `x`."));
    expect_true(hover.contains("**Parameters**\n- `x` — the value"));
    expect_equal(
        definition_text(context, at(text, "twice(1)", 1)), "imported.pep: twice(x: int): int { return x * 2; }"
    );
    expect_equal(definition_text(context, at(text, "\"imported\"", 1)), "imported.pep: ## Doubles `x`.");
}

[Test]
hover_shows_the_docs_of_members_and_inferred_types() {
    var text = "struct Core {\n    ## Whether the task finished.\n    var finished: bool;\n}\n"
        + "struct Worker {\n    ## The task's shared state.\n    var core: Core;\n\n"
        + "    ## Adds `by`.\n    add(by: int): int { return by; }\n}\n"
        + "worker_of(): Worker { return Worker(); }\n"
        + "main(): int {\n    var worker = worker_of();\n    var done = worker.core.finished;\n    return worker.add(1);\n}\n";
    var context = analyzed(temp_file("inferred.pep", text), text);
    expect_true(hover_text(context, at(text, "worker.core", 0)).contains("`worker` — `Worker`"));
    var core = hover_text(context, at(text, "core.finished", 0));
    expect_true(core.contains("`Core`"));
    expect_true(core.contains("shared state"));
    var finished = hover_text(context, at(text, "finished;\n    return", 0));
    expect_true(finished.contains("`bool`"));
    expect_true(finished.contains("task finished"));
    expect_true(hover_text(context, at(text, "done", 0)).contains("`bool`"));
    var add = hover_text(context, at(text, "add(1)", 0));
    expect_true(add.contains("`add(by: int): int`"));
    expect_true(add.contains("Adds `by`."));
    expect_equal(definition_text(context, at(text, "add(1)", 0)), "inferred.pep: add(by: int): int { return by; }");
    expect_equal(definition_text(context, at(text, "core.finished", 0)), "inferred.pep: core: Core;");
}

[Test]
definition_without_an_analysis_reads_the_text() {
    # An edit since the last analysis: the parse alone answers for locals,
    # parameters and the file's own declarations.
    var text = "thrice(x: int): int {\n    var total = x * 3;\n    return total;\n}\nmain(): int { return thrice(1); }\n";
    var context = Context(lsp.TextDocument("file:///nowhere/a.pep", text), parse.parse(text).value());
    expect_equal(definition_text(context, at(text, "thrice(1)", 2)), "a.pep: thrice(x: int): int {");
    expect_equal(definition_text(context, at(text, "total;", 1)), "a.pep: total = x * 3;");
    expect_equal(definition_text(context, at(text, "x * 3", 0)), "a.pep: x: int): int {");
    expect_true(hover_text(context, at(text, "x * 3", 0)).contains("`x` — `int`"));
}
