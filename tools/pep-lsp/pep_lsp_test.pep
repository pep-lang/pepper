# pep-lsp's tests: the outline, and analysis of documents on disk.

import [Directory, File, Path] from io;
import lsp;
import compiler.parse;
import "analysis";
import "symbols";

# Writes `text` to `name` in a new temporary folder; returns its URI.
temp_file(name: String, text: String): String {
    var folder = Directory.temp().join(Path($"pep-lsp-test-{name}"));
    Directory.create_all(folder);
    var path = folder.join(Path(name));
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
