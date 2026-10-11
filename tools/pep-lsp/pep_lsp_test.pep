# pep-lsp's tests: the outline, analysis of documents on disk, and hover
# and go-to-definition.

import [Channel, Thread] from async;
import [Directory, File, Path] from io;
import json;
import [JsonValue] from json;
import compiler.link;
import lsp;
import compiler.parse;
import "actions";
import "analysis";
import "arguments";
import "completion";
import "edits";
import "hints";
import "navigate";
import "platforms";
import "server";
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
    Directory.create_all(path.parent().value());
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
reports_every_syntax_error_and_the_brace_a_missing_brace_closes() {
    var text = "f(): int {\n    return 0\n}\n\ng() {\n    var x = ;\n\nh() {\n}\n";
    var analysis = analyze("file:///nowhere/a.pep", text);
    expect_equal(analysis.outcome, "did not parse");
    expect_equal(analysis.diagnostics.count, 3 as ulong);
    expect_equal(analysis.diagnostics[0].message, "expected ';'");
    expect_equal(analysis.diagnostics[1].message, "expected expression");
    expect_equal(analysis.diagnostics[1].range.start.line, 5);
    # `g`'s `}` is due before `h`, which starts a line no deeper than `g`.
    var unclosed = analysis.diagnostics[2];
    expect_equal(unclosed.message, "expected '}'");
    expect_equal(unclosed.range.start.line, 7);
    var related = unclosed.related_information.value();
    expect_equal(related[0].message, "to match this '{'");
    expect_equal(related[0].location.range.start.line, 4);
    expect_equal(related[0].location.range.start.character, 4);
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

[Test]
shows_an_error_in_another_file_at_the_start() {
    # The document is fine, but a file it imports is not: without the
    # error, the analysis stops before sema with nothing to show.
    temp_file_in("other_error.pep", "helper.pep", "import nowhere_to_be_found;\nexport helper(): int { return 0; }\n");
    var text = "import \"helper\";\nmain(): int {\n    return helper();\n}\n";
    var analysis = analyze(temp_file_in("other_error.pep", "main.pep", text), text);
    expect_equal(analysis.outcome, "found an error");
    expect_equal(analysis.diagnostics.count, 1 as ulong);
    expect_true(analysis.diagnostics[0].message.contains("helper.pep: "));
    expect_true(analysis.diagnostics[0].message.contains("nowhere_to_be_found"));
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

[Test]
edit_map_carries_offsets_around_the_edit() {
    var earlier = "var alpha = 1;\nvar beta = 2;\n";
    var current = "var alpha = 1;\nvar gamma = 3;\nvar beta = 2;\n";
    var edits = EditMap(earlier, current);
    # Before the edit, and after it.
    expect_equal(edits.to_earlier(current, at(current, "alpha", 2)).value(), at(earlier, "alpha", 2));
    expect_equal(edits.to_earlier(current, at(current, "beta", 1)).value(), at(earlier, "beta", 1));
    # Inside it.
    expect_true(edits.to_earlier(current, at(current, "gamma", 1)).is_empty());
    var before = lsp.TextDocument("", earlier);
    var after = lsp.TextDocument("", current);
    var beta = before.range_of(at(earlier, "beta", 0), at(earlier, "beta", 4));
    var moved = edits.range_to_current(earlier, current, beta).value();
    expect_equal(after.offset_at(moved.start), at(current, "beta", 0));
    expect_equal(after.offset_at(moved.end), at(current, "beta", 4));
    # An empty range at the start of the line a new line went above moves
    # down with it.
    var start = lsp.Range(lsp.Position(1, 0), lsp.Position(1, 0));
    expect_equal(edits.range_to_current(earlier, current, start).value().start.line, 2);

    # A name on an edited line does not map: editing `p.x` to `q.x`
    # changes what `x` is.
    expect_true(EditMap("f(ab);", "f(abc);").to_earlier("f(abc);", 3).is_empty());
    var p = "var a = p.x;\nb;\n";
    var q = "var a = q.x;\nb;\n";
    edits = EditMap(p, q);
    expect_true(edits.to_earlier(q, at(q, "x;", 0)).is_empty());
    expect_equal(edits.to_earlier(q, at(q, "b;", 0)).value(), at(p, "b;", 0));
    # So do answers that came from it, such as a hint around `x`.
    var earlier_p = lsp.TextDocument("", p);
    var x = earlier_p.range_of(at(p, "x;", 0), at(p, "x;", 1));
    expect_true(edits.line_range_to_current(p, q, x).is_empty());
    var b = earlier_p.range_of(at(p, "b;", 0), at(p, "b;", 1));
    var kept = edits.line_range_to_current(p, q, b).value();
    expect_equal(kept.start.line, b.start.line);
    expect_equal(kept.start.character, b.start.character);
    expect_equal(kept.end.character, b.end.character);

    # An edit inside a multi-byte character splits at a character boundary.
    var acute = "a = \"é\";\nb";
    var grave = "a = \"è\";\nb";
    expect_equal(EditMap(acute, grave).to_earlier(grave, grave.size - 1).value(), acute.size - 1);
}

[Test]
answers_after_an_edit_read_the_last_passed_analysis() {
    var text = "## Triples `x`.\nthrice(x: int): int { return x * 3; }\nmain(): int {\n    return thrice(1);\n}\n";
    var uri = temp_file("edited.pep", text);
    var ready = analyze(uri, text);
    expect_equal(ready.outcome, "passed");
    var some = Optional<Analysis>.Value(ready);

    # A line above: the name moved, the old analysis answers.
    var edited = "# A note.\n" + text;
    var document = lsp.TextDocument(uri, edited);
    var hover = hover_across_edits(document, some, some, at(edited, "thrice(1)", 1)).value().contents.value;
    expect_true(hover.contains("Triples `x`."));
    expect_true(hover.contains("Checking your latest edit"));
    var found = definition_across_edits(document, some, some, at(edited, "thrice(1)", 1));
    expect_equal(document.offset_at(found[0].range.start), at(edited, "thrice(x", 0));

    # Inside the edit: the current text answers, without sema.
    edited = text.replace("return thrice(1);", "return twice(1);") + "twice(x: int): int { return x * 2; }\n";
    document = lsp.TextDocument(uri, edited);
    found = definition_across_edits(document, some, some, at(edited, "twice(1)", 1));
    expect_equal(document.offset_at(found[0].range.start), at(edited, "twice(x", 0));
}

# The labels of `items`, in order.
labels(items: lsp.CompletionItem[]): String[] {
    var out = Array<String>();
    for (var item in items) {
        out.append(item.label);
    }
    return out;
}

# The labels of the items that insert `name = `, in order.
argument_labels(items: lsp.CompletionItem[]): String[] {
    var out = Array<String>();
    for (var item in items) {
        if (item.insert_text is Value(inserted)) {
            if (inserted == item.label + " = ") {
                out.append(item.label);
            }
        }
    }
    return out;
}

[Test]
completion_after_an_enum_name_lists_its_cases() {
    var text = "## A traffic light color.\nenum Color { Red, Amber = 1, Green }\n"
        + "enum Shape { Circle(radius: int), Empty }\n"
        + "main(): int {\n    var c = Color.;\n    return 0;\n}\n";
    var document = lsp.TextDocument("file:///nowhere/a.pep", text);
    var none = Optional<Analysis>.Empty;
    var items = completion_at(document, none, none, at(text, "Color.;", 6));
    expect_equal(", ".join(labels(items)), "Red, Amber, Green, from_value");
    expect_equal(items[0].kind.value(), lsp.COMPLETION_ENUM_MEMBER);
    expect_equal(items[1].detail.value(), "Color.Amber");

    text = text.replace("Color.;", "Shape.;");
    document = lsp.TextDocument("file:///nowhere/a.pep", text);
    items = completion_at(document, none, none, at(text, "Shape.;", 6));
    expect_equal(", ".join(labels(items)), "Circle, Empty");
    expect_equal(items[0].detail.value(), "Shape.Circle(radius: int)");
}

[Test]
completion_offers_keywords_and_names_in_scope() {
    var text = "struct Box {\n    var size: int;\n    grow(by: int): int {\n        var next = size + by;\n        return n;\n    }\n}\n"
        + "make(): Box { return Box(); }\n";
    var document = lsp.TextDocument("file:///nowhere/a.pep", text);
    var none = Optional<Analysis>.Empty;
    var found = labels(completion_at(document, none, none, at(text, "n;", 1)));
    for (var expected in ["return", "next", "by", "size", "grow", "make", "Box"]) {
        expect_true(found.contains(expected));
    }
}

[Test]
completion_in_an_argument_list_offers_parameter_names() {
    var resized = "struct Window {\n    var width: int;\n    var height: int;\n\n"
        + "    construct(this.width = 0, this.height = 0) {}\n\n"
        + "    [Alias(\"w\", \"width\")]\n    resize(width: int, height: int) {\n        this.width = width;\n        this.height = height;\n    }\n}\n\n"
        + "[Alias(\"count\", \"times\")]\nrepeat(text: String, times: int): String { return text; }\n\n"
        + "main(): int {\n    var window = Window(640, 480);\n    window.resize(800, height = 600);\n"
        + "    var size = 4;\n    var s = repeat(\"ab\", size);\n    return 0;\n}\n";
    var none = Optional<Analysis>.Empty;
    var names = (text: String, offset: ulong) => {
        var document = lsp.TextDocument("file:///nowhere/a.pep", text);
        return ", ".join(argument_labels(completion_at(document, none, none, offset)));
    };
    # A method, after a named argument: its other parameter and the alias.
    var text = resized.replace("window.resize(800, height = 600)", "window.resize(height = 600, )");
    expect_equal(names(text, at(text, ", )", 2)), "width, w");
    # A free function, while its first argument is typed.
    text = resized.replace("repeat(\"ab\", size)", "repeat(te)");
    expect_equal(names(text, at(text, "te)", 2)), "text, times, count");
    # A constructor.
    text = resized.replace("Window(640, 480)", "Window()");
    expect_equal(names(text, at(text, "Window()", 7)), "width, height");
    # Not inside an argument.
    expect_equal(names(resized, at(resized, "640", 2)), "");
}

# A struct `[Implicit]` constructors convert to, and values converted.
const CONVERTED = "struct Name {\n    var text: String;\n    [Implicit]\n    construct(text: String = \"\") { this.text = text; }\n}\n\ngreet(n: Name): String { return n.text; }\n\nmain(): int {\n    var who = \"ada\";\n    greet(who);\n    greet(\"bob\");\n    var typed: Name = who;\n    var plain = \"stays a String\";\n    return 0;\n}\n";

# The hints of `document` from `ready`, each as `line:character label`.
hint_list(document: lsp.TextDocument, ready: Analysis, conversions: bool, parameters: bool): String {
    var all = lsp.Range(lsp.Position(0, 0), lsp.Position(1000, 0));
    var out = Array<String>();
    for (var hint in inlay_hints(document, Optional<Analysis>.Value(ready), all, conversions, parameters)) {
        out.append($"{hint.position.line}:{hint.position.character} {hint.label}");
    }
    return ", ".join(out);
}

[Test]
hover_and_inlay_hints_show_implicit_conversions() {
    var text = CONVERTED;
    var uri = temp_file("converted.pep", text);
    var context = analyzed(uri, text);
    var note = "Converted to `Name` by its `[Implicit]` constructor from `String`.";
    expect_true(hover_text(context, at(text, "greet(who)", 7)).contains(note));
    expect_true(hover_text(context, at(text, "\"bob\"", 2)).contains(note));
    expect_true(hover_text(context, at(text, "= who", 3)).contains(note));
    expect_false(hover_text(context, at(text, "\"stays", 2)).contains("Converted"));

    var ready = analyze(uri, text);
    var document = lsp.TextDocument(uri, text);
    expect_equal(
        hint_list(document, ready, true, false), "10:10 Name(, 10:13 ), 11:10 Name(, 11:15 ), 12:22 Name(, 12:25 )"
    );
    # A line above moves them down.
    var edited = "# A note.\n" + text;
    expect_equal(
        hint_list(lsp.TextDocument(uri, edited), ready, true, false),
        "11:10 Name(, 11:13 ), 12:10 Name(, 12:15 ), 13:22 Name(, 13:25 )"
    );
    # An edit on a hint's line drops it.
    edited = text.replace("greet(\"bob\");", "greet(\"bobby\");");
    expect_equal(
        hint_list(lsp.TextDocument(uri, edited), ready, true, false), "10:10 Name(, 10:13 ), 12:22 Name(, 12:25 )"
    );
}

[Test]
inlay_hints_name_literal_arguments() {
    var text = "struct Window {\n    var width: int;\n    var height: int;\n\n"
        + "    construct(this.width = 0, this.height = 0) {}\n\n"
        + "    resize(width: int, height: int) {\n        this.width = width;\n        this.height = height;\n    }\n}\n\n"
        + "repeat(text: String, times: int): String { return text; }\n\n"
        + "main(): int {\n    var window = Window(640, 480);\n    window.resize(800, height = 600);\n"
        + "    var size = 4;\n    var s = repeat(\"ab\", size);\n    return 0;\n}\n";
    var uri = temp_file("resized.pep", text);
    var ready = analyze(uri, text);
    expect_equal(ready.outcome, "passed");
    # A named argument and a variable need no hint.
    expect_equal(
        hint_list(lsp.TextDocument(uri, text), ready, false, true),
        "15:24 width:, 15:29 height:, 16:18 width:, 18:19 text:"
    );
}

# The titles of `actions`, then each one's edits as `line:character-line:character text`.
action_list(actions: lsp.CodeAction[]): String {
    var out = Array<String>();
    for (var action in actions) {
        var edits = Array<String>();
        for (var (_, list) in action.edit.value().changes) {
            for (var e in list) {
                var r = e.range;
                edits.append($"{r.start.line}:{r.start.character}-{r.end.line}:{r.end.character} {e.new_text}");
            }
        }
        out.append(action.title + " [" + "; ".join(edits) + "]");
    }
    return " | ".join(out);
}

# The actions of `analysis` at `line:character`.
actions_at(analysis: Analysis, line: int, character: int): String {
    var document = lsp.TextDocument(analysis.uri, analysis.text);
    var at = lsp.Range(lsp.Position(line, character), lsp.Position(line, character));
    return action_list(code_actions(document, Optional<String>.Value(analysis.text), analysis.actions, at));
}

[Test]
syntax_offers_quick_fixes() {
    var text = "struct S {\n    var x: int;\n    new(this.x = 1) {}\n}\n";
    var document = lsp.TextDocument("file:///nowhere/a.pep", text);
    var none = Optional<String>.Empty;
    var at = (line: int, character: int) => lsp.Range(lsp.Position(line, character), lsp.Position(line, character));
    var actions = code_actions(document, none, Array<lsp.CodeAction>(), at(2, 5));
    expect_equal(action_list(actions), "Replace `new` with `construct` [2:4-2:7 construct]");
    expect_equal(actions[0].kind.value(), lsp.QUICK_FIX);
    var shown = actions[0].diagnostics.value()[0];
    expect_equal(shown.severity.value(), lsp.SEVERITY_WARNING);
    expect_equal(shown.tags.value()[0], lsp.TAG_DEPRECATED);
    # Nothing to fix away from the warning, or once it is fixed.
    expect_equal(code_actions(document, none, Array<lsp.CodeAction>(), at(0, 0)).count, 0 as ulong);
    var fixed = lsp.TextDocument("file:///nowhere/a.pep", text.replace("new(", "construct("));
    expect_equal(code_actions(fixed, none, Array<lsp.CodeAction>(), at(2, 5)).count, 0 as ulong);

    text = "main(): int {\n    var total = 1\n    return total;\n}\n";
    document = lsp.TextDocument("file:///nowhere/a.pep", text);
    actions = code_actions(document, none, Array<lsp.CodeAction>(), at(1, 17));
    expect_equal(action_list(actions), "Insert ';' [1:17-1:17 ;]");
    expect_equal(actions[0].diagnostics.value()[0].severity.value(), lsp.SEVERITY_ERROR);
}

[Test]
deprecated_declarations_offer_quick_fixes() {
    var text = "struct Counter {\n    var value: int;\n    [Deprecated(\"use 'copy' instead\", \"copy\")]\n"
        + "    clone(): Counter { return this; }\n    copy(): Counter { return this; }\n}\n"
        + "[Deprecated(\"use 'twice' instead\", \"twice\")]\ndup(x: int): int { return x * 2; }\n"
        + "twice(x: int): int { return x * 2; }\n"
        + "test(): int {\n    var c = Counter();\n    var d = c.clone();\n    return dup(d.value);\n}\n";
    var analysis = analyze(temp_file("deprecated.pep", text), text);
    expect_equal(actions_at(analysis, 11, 16), "Replace 'clone' with 'copy' [11:14-11:19 copy]");
    expect_equal(actions_at(analysis, 12, 12), "Replace 'dup' with 'twice' [12:11-12:14 twice]");
}

[Test]
sending_a_variable_offers_move_and_copy() {
    var text = "import async;\n\nconst lines = async.Channel<String>();\n\nmain(): int {\n"
        + "    var line = \"hello\";\n    lines.send(line);\n    return 0;\n}\n";
    var analysis = analyze(temp_file("send_named.pep", text), text);
    expect_equal(
        actions_at(analysis, 6, 17),
        "Hand 'line' over with 'move(line)' [6:15-6:19 move(line)] | Pass a copy with 'copy(line)' [6:15-6:19 copy(line)]"
    );
}

[Test]
a_match_missing_cases_offers_to_add_them() {
    var text = "## A traffic light color.\nenum Color { Red, Amber = 1, Green }\n\n"
        + "score(c: Color): int {\n    match (c) {\n        Red => { return 1; }\n    }\n    return 0;\n}\n";
    var analysis = analyze(temp_file("missing_arms.pep", text), text);
    expect_equal(
        actions_at(analysis, 4, 6),
        "Add the missing cases of 'Color' [6:0-6:0         Amber => {}\n        Green => {}\n]"
    );
    expect_equal(actions_at(analysis, 0, 0), "");
}

# A target for `os` on x86-64.
target_of(os: String): link.Target {
    var target = link.Target();
    target.os = os;
    target.arch = "x86_64";
    return target;
}

[Test]
code_for_other_platforms_is_dimmed() {
    var text = "[Target(OS(Windows))]\nimport \"win_only\";\n\n[Target(OS(Linux))]\nopen_linux(): int { return 1; }\n\n"
        + "[Target(OS(Windows))]\nopen_windows(): int { return 2; }\n\nstruct File {\n    var size: int;\n\n"
        + "    [Target(OS(Windows))]\n    construct() {}\n\n    [Target(OS(Windows))]\n    close() {}\n\n"
        + "    read(): int {\n        [Target(OS(Windows))] {\n            return 1;\n        }\n"
        + "        [Target(!OS(Windows))] {\n            return 2;\n        }\n"
        + "        for (var i in [1, 2]) {\n            [Target(OS(Windows))] {\n                return i;\n            }\n        }\n"
        + "        return 0;\n    }\n}\n";
    var module = parse.parse(text).value();
    var firsts = Array<String>();
    var lasts = Array<String>();
    for (var span in inactive_regions(text, module, target_of("linux"))) {
        var lines = text.substr_bytes(span.start, span.end - span.start).split("\n");
        firsts.append(lines[0]);
        lasts.append(lines[lines.count - 1].trim());
    }
    # Not the constructor: it is compiled whatever its attributes.
    expect_equal(firsts.count, 5 as ulong);
    for (var first in firsts) {
        expect_true(first.starts_with("[Target(OS(Windows))]"));
    }
    expect_equal(" | ".join(lasts), "import \"win_only\" | open_windows(): int { return 2; } | close() {} | } | }");
    var hints = inactive_hints(lsp.TextDocument("file:///a.pep", text), module, target_of("linux"));
    expect_equal(hints.count, 5 as ulong);
    expect_equal(hints[0].tags.value()[0], lsp.TAG_UNNECESSARY);
    expect_true(hints[0].message.contains("Linux x86_64"));
}

[Test]
a_file_for_another_os_is_analyzed_for_it() {
    var linux_only = "struct Socket { var handle: int; }\n[Target(OS(Linux))]\nopen_socket(): Socket { return Socket(); }\n"
        + "[Target(OS(Linux))]\nhandle_of(): int {\n    var socket = open_socket();\n    return socket.handle;\n}\n";
    var module = parse.parse(linux_only).value();
    expect_equal(analysis_os(linux_only, module, target_of("windows")), "linux");
    expect_equal(analysis_os(linux_only, module, target_of("linux")), "linux");
    # Analyzed as Linux, its names have types; for Windows its code is
    # still dimmed.
    var context = analyzed(temp_file("linux_only.pep", linux_only), linux_only);
    var shown = hover_text(context, at(linux_only, "socket.handle", 0));
    expect_true(shown.contains("`socket` — `Socket`"));
    expect_equal(
        inactive_hints(lsp.TextDocument("file:///a.pep", linux_only), module, target_of("windows")).count, 2 as ulong
    );
    # Code for both the build target and another OS: the build target's.
    var both = linux_only + "[Target(OS(Windows))]\nwindows_only(): int { return 1; }\n";
    expect_equal(analysis_os(both, parse.parse(both).value(), target_of("windows")), "windows");
    # A mostly portable file stays on the build target, so a call the
    # build target rejects still shows its error.
    var mixed = "[Target(OS(Linux))]\nfoo(): int { return 1; }\nbar(): int { return foo(); }\n"
        + "baz(): int { return bar() + 1; }\nqux(): int { return baz() + bar() + 2; }\n";
    expect_equal(analysis_os(mixed, parse.parse(mixed).value(), target_of("windows")), "windows");
}

[Test]
build_options_come_from_the_initialization_options() {
    var options = json.parse("{\"buildOptions\": [\"USE_ZLIB\", \"LOG_LEVEL=2\", \"not valid\", 3]}").value();
    var parsed = build_options(Optional<JsonValue>.Value(options));
    expect_equal(parsed.count, 2 as ulong);
    expect_equal(parsed["USE_ZLIB"], "1");
    expect_equal(parsed["LOG_LEVEL"], "2");
    expect_equal(build_options(Optional<JsonValue>.Empty).count, 0 as ulong);
}

# Ported from tools/lsp/src/tests.rs. Each test collects its failed checks
# (label: actual value) and reports them all at its end, so one failure
# does not hide the rest.

const GEOMETRY_MODULE = "import \"shapes\";\n\nexport struct Point { var x: int; var y: int; }\nexport make(x: int, y: int): Point {\n    var p = Point();\n    p.x = x;\n    p.y = y;\n    return p;\n}\nexport area as rect_area;\nexport Box;\n## Half of `x`.\nhalf(x: int): int { return x / 2; }\n";
const GEOMETRY_SHAPES = "import \"module\";\n\nexport area(w: int, h: int): int { return w * h; }\nexport struct Box<T> { var value: T; }\nexport unit(): Point { return make(half(2), 1); }\n";
const SOLIDS_MODULE = "export * from \"cube\";\nexport [volume as size] from \"cube\";\n";
const SOLIDS_CUBE = "export volume(s: int): int { return s * s * s; }\nexport edge(s: int): int { return s; }\n";
const UTIL = "export twice(x: int): int { return x * 2; }\nstruct Tally { var n: int; }\n## Counts; ask jane@corp.com.\nexport tally(): Tally { return Tally(); }\n";

# Writes the Rust tests' file tree (`deps/geometry`, `deps/solids`,
# `util.pep`) and `main` as `main.pep` to the temporary folder for `test`,
# with a `pep.toml` making `deps` an import folder (pep-lsp takes no `-I`);
# returns the URI of `root` there.
tree(test: String, main: String, root: String): String {
    temp_file_in(test, "pep.toml", "[package]\nname = \"app\"\n\n[build]\ninclude = [\"deps\"]\n");
    temp_file_in(test, "deps/geometry/module.pep", GEOMETRY_MODULE);
    temp_file_in(test, "deps/geometry/shapes.pep", GEOMETRY_SHAPES);
    temp_file_in(test, "deps/solids/module.pep", SOLIDS_MODULE);
    temp_file_in(test, "deps/solids/cube.pep", SOLIDS_CUBE);
    temp_file_in(test, "util.pep", UTIL);
    temp_file_in(test, "main.pep", main);
    return lsp.path_to_uri(Directory.temp().join(Path($"pep-lsp-test-{test}")).join(Path(root)).to_string());
}

# How `analysis` went, with its diagnostics when it did not pass.
outcome_of(analysis: Analysis): String {
    var out = analysis.outcome;
    if (out != "passed") {
        for (var d in analysis.diagnostics) {
            out = out + " | " + d.message;
        }
    }
    return out;
}

# The context of the analysis of the file `uri`, passed or not.
context_for(uri: String): Context {
    var text = File.read_to_string(Path(lsp.uri_to_path(uri).value())).value();
    var analysis = analyze(uri, text);
    return context_of(lsp.TextDocument(uri, text), Optional<Analysis>.Value(analysis)).value();
}

# `tree`, then the context of `root`'s analysis, which must pass.
loaded(test: String, main: String, root: String): Context {
    var uri = tree(test, main, root);
    var text = File.read_to_string(Path(lsp.uri_to_path(uri).value())).value();
    var analysis = analyze(uri, text);
    expect_equal(outcome_of(analysis), "passed");
    return context_of(lsp.TextDocument(uri, text), Optional<Analysis>.Value(analysis)).value();
}

# `tree`, then the context of `root`'s analysis, passed or not.
loaded_anyway(test: String, main: String, root: String): Context {
    return context_for(tree(test, main, root));
}

# The byte offset of the `nth` (from 0) `needle` in `text`, plus `delta`.
at_nth(text: String, needle: String, nth: int, delta: ulong): ulong {
    var found = text.find(needle);
    var n = 0;
    while (n < nth and found >= 0) {
        found = text.find(needle, found as ulong + 1);
        n = n + 1;
    }
    expect_true(found >= 0);
    return found as ulong + delta;
}

# The folder and name of the file of the first definition at `offset`.
def_file(context: Context, offset: ulong): String {
    var locations = definition_at(context, offset);
    if (locations.count == 0) {
        return "<none>";
    }
    var path = Path(lsp.uri_to_path(locations[0].uri).value());
    var parent = path.parent().value().file_name().value();
    return $"{parent}/{path.file_name().value()}";
}

# The text of the first definition at `offset`, to the end of its line.
def_rest(context: Context, offset: ulong): String {
    var shown = definition_text(context, offset);
    var colon = shown.find(": ");
    if (colon < 0) {
        return "<none>";
    }
    return shown.substr_bytes(colon as ulong + 2, shown.size - colon as ulong - 2);
}

# Records `label` and `actual` in `failed` unless `ok`.
check(failed: String[], label: String, ok: bool, actual: String) {
    if (!ok) {
        failed.append($"[{label}] got: {actual}");
    }
}

# Fails with every check `failed` recorded.
all_passed(failed: String[]) {
    expect_equal("\n".join(failed), "");
}

const ALIAS = "import geometry as g;\ntest(): int {\n    var p: g.Point = g.make(1, 2);\n    var b = g.Box<int>();\n    b.value = g.rect_area(2, 5);\n    return p.y + b.value;\n}\n";

[Test]
qualified_function_leads_to_its_module_file() {
    var c = loaded("qualified_fn", ALIAS, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var make = at(text, "g.make", 3);
    var h = hover_text(c, make);
    check(failed, "hover signature", h.contains("make(x: int, y: int): Point"), h);
    check(failed, "hover file", h.contains("geometry/module.pep"), h);
    check(failed, "file", def_file(c, make) == "geometry/module.pep", def_file(c, make));
    check(failed, "rest", def_rest(c, make).starts_with("make(x: int"), def_rest(c, make));
    all_passed(failed);
}

[Test]
qualified_reexport_leads_to_the_declaring_file() {
    var c = loaded("qualified_reexport", ALIAS, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var o = at(text, "rect_area", 0);
    check(failed, "file", def_file(c, o) == "geometry/shapes.pep", def_file(c, o));
    check(failed, "rest", def_rest(c, o).starts_with("area(w: int"), def_rest(c, o));
    all_passed(failed);
}

[Test]
qualifier_leads_to_the_module() {
    var c = loaded("qualifier", ALIAS, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var q = at(text, "g.make", 0);
    check(failed, "hover", hover_text(c, q).contains("geometry/module.pep"), hover_text(c, q));
    check(failed, "definition", def_file(c, q) == "geometry/module.pep", def_file(c, q));
    var m = at(text, "geometry", 1);
    check(failed, "import name", def_file(c, m) == "geometry/module.pep", def_file(c, m));
    all_passed(failed);
}

[Test]
a_project_dependency_leads_to_its_fetched_files() {
    var test = "project_dependency";
    var package = ".pep/deps/github.com/someone/geometry/";
    temp_file_in(
        test, "pep.toml", "[package]\nname = \"app\"\n\n[dependencies]\ngeo = { github = \"someone/geometry\" }\n"
    );
    temp_file_in(test, package + "module.pep", "export area(w: int, h: int): int { return w * h; }\n");
    temp_file_in(test, package + "solids/module.pep", "export volume(s: int): int { return s * s * s; }\n");
    var text = "import geo;\nimport geo.solids;\ntest(): int {\n    return geo.area(2, 3) + solids.volume(2);\n}\n";
    var uri = temp_file_in(test, "main.pep", text);
    var analysis = analyze(uri, text);
    expect_equal(outcome_of(analysis), "passed");
    var c = context_of(lsp.TextDocument(uri, text), Optional<Analysis>.Value(analysis)).value();
    var failed = Array<String>();
    var area = at(text, "geo.area", 4);
    check(failed, "area file", def_file(c, area) == "geometry/module.pep", def_file(c, area));
    check(failed, "area rest", def_rest(c, area).starts_with("area(w: int"), def_rest(c, area));
    var volume = at(text, "solids.volume", 7);
    check(failed, "volume file", def_file(c, volume) == "solids/module.pep", def_file(c, volume));
    all_passed(failed);
}

[Test]
qualified_types_lead_to_their_declarations() {
    var c = loaded("qualified_types", ALIAS, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var point = at(text, "g.Point", 2);
    check(failed, "hover", hover_text(c, point).contains("struct Point"), hover_text(c, point));
    check(failed, "Point file", def_file(c, point) == "geometry/module.pep", def_file(c, point));
    check(failed, "Point rest", def_rest(c, point).starts_with("Point {"), def_rest(c, point));
    var box = at(text, "g.Box", 3);
    check(failed, "Box file", def_file(c, box) == "geometry/shapes.pep", def_file(c, box));
    check(failed, "Box rest", def_rest(c, box).starts_with("Box<T>"), def_rest(c, box));
    all_passed(failed);
}

[Test]
listed_symbols_and_aliases_lead_to_their_declarations() {
    var main = "import [make, Point as Pt, rect_area as area] from geometry;\ntest(): int {\n"
        + "    var p: Pt = make(2, 3);\n    return area(p.x, p.y);\n}\n";
    var c = loaded("listed", main, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var use = at(text, "area(p.x", 0);
    var h = hover_text(c, use);
    check(failed, "alias hover", h.starts_with("`area` — `area(w: int, h: int): int`"), h);
    check(failed, "alias file", def_file(c, use) == "geometry/shapes.pep", def_file(c, use));
    check(failed, "Pt", def_rest(c, at(text, "Pt =", 0)).starts_with("Point {"), def_rest(c, at(text, "Pt =", 0)));
    check(failed, "make", def_rest(c, at(text, "make(2", 0)).starts_with("make(x"), def_rest(c, at(text, "make(2", 0)));
    var entry = at(text, "rect_area as", 0);
    check(failed, "rect_area entry", def_rest(c, entry).starts_with("area(w"), def_rest(c, entry));
    var pt = at(text, "as Pt", 3);
    check(failed, "Pt entry", def_rest(c, pt).starts_with("Point {"), def_rest(c, pt));
    all_passed(failed);
}

[Test]
file_import_leads_to_the_file() {
    var c = loaded("file_import", "import \"util\";\ntest(): int { return twice(3); }\n", "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var twice = at(text, "twice", 0);
    check(failed, "file", def_file(c, twice).ends_with("/util.pep"), def_file(c, twice));
    check(failed, "rest", def_rest(c, twice).starts_with("twice(x"), def_rest(c, twice));
    var path = at(text, "\"util\"", 2);
    check(failed, "import path", def_file(c, path).ends_with("/util.pep"), def_file(c, path));
    all_passed(failed);
}

[Test]
reexport_leads_to_the_reexported_declaration() {
    var c = loaded("reexport", "", "deps/geometry/module.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var o = at(text, "export area", 7);
    check(failed, "file", def_file(c, o) == "geometry/shapes.pep", def_file(c, o));
    check(failed, "rest", def_rest(c, o).starts_with("area(w"), def_rest(c, o));
    all_passed(failed);
}

[Test]
export_from_leads_to_the_source_and_its_declarations() {
    var main = "import solids;\ntest(): int {\n    var e = solids.edge(2);\n    return e + solids.size(1);\n}\n";
    var c = loaded("export_from_use", main, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var edge = at(text, "edge", 0);
    check(failed, "edge file", def_file(c, edge) == "solids/cube.pep", def_file(c, edge));
    check(failed, "edge rest", def_rest(c, edge).starts_with("edge(s"), def_rest(c, edge));
    var size = at(text, "size", 0);
    check(failed, "size rest", def_rest(c, size).starts_with("volume(s"), def_rest(c, size));

    c = loaded("export_from_lines", "", "deps/solids/module.pep");
    text = c.document.text;
    var cube = at(text, "\"cube\"", 2);
    check(failed, "cube source", def_file(c, cube) == "solids/cube.pep", def_file(c, cube));
    var volume = at(text, "volume", 0);
    check(failed, "volume file", def_file(c, volume) == "solids/cube.pep", def_file(c, volume));
    check(failed, "volume rest", def_rest(c, volume).starts_with("volume(s"), def_rest(c, volume));
    all_passed(failed);
}

[Test]
prelude_function_leads_to_the_runtime() {
    var c = loaded("prelude", "test(): int { assert(true, \"ok\"); return 0; }\n", "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var o = at(text, "assert", 0);
    check(failed, "file", def_file(c, o) == "runtime/internals.pep", def_file(c, o));
    check(failed, "rest", def_rest(c, o).starts_with("assert(condition"), def_rest(c, o));
    all_passed(failed);
}

[Test]
built_in_leads_to_its_declaration_in_the_runtime() {
    var main = "struct P { var x: int; }\ntest(): int {\n    static {\n        for (var f in reflect.properties<P>()) {\n"
        + "            reflect.print(f.name);\n        }\n    }\n    assert(true, \"ok\");\n    return 0;\n}\n";
    var c = loaded("built_in", main, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var properties = at(text, "properties", 2);
    check(failed, "properties file", def_file(c, properties) == "runtime/reflect.pep", def_file(c, properties));
    check(failed, "properties rest", def_rest(c, properties).starts_with("properties<T>()"), def_rest(c, properties));
    var print = at(text, "print", 1);
    check(failed, "print file", def_file(c, print) == "runtime/reflect.pep", def_file(c, print));
    check(failed, "print rest", def_rest(c, print).starts_with("print<T>(value"), def_rest(c, print));
    var shown = hover_text(c, properties);
    check(failed, "hover", shown.starts_with("`reflect.properties` — `reflect.properties<T>(): List<Member>`"), shown);
    check(failed, "hover docs", shown.contains("The public fields"), shown);
    var assert = at(text, "assert", 0);
    check(failed, "assert file", def_file(c, assert) == "runtime/internals.pep", def_file(c, assert));
    all_passed(failed);
}

[Test]
intrinsics_lead_to_their_declarations_in_the_runtime() {
    var main = "test(location: __ptr<char> = __caller_location()): ulong {\n    var p: __ptr<int> = __null;\n"
        + "    var z = __default<int>();\n    return sizeof<int>();\n}\n";
    var c = loaded("intrinsics", main, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var expect_intrinsic = (needle: String, delta: ulong, starts: String) => {
        var o = at(text, needle, delta);
        check(failed, needle + " file", def_file(c, o) == "runtime/builtins.pep", def_file(c, o));
        check(failed, needle + " rest", def_rest(c, o).starts_with(starts), def_rest(c, o));
    };
    expect_intrinsic("__caller_location", 2, "__caller_location()");
    expect_intrinsic("__ptr", 2, "__ptr<T>");
    expect_intrinsic("__null", 2, "null_pointer");
    expect_intrinsic("__default", 2, "__default<T>()");
    expect_intrinsic("sizeof", 1, "size_of<T>()");
    var shown = hover_text(c, at(text, "__caller_location", 2));
    check(failed, "hover", shown.contains("The place of the call"), shown);
    all_passed(failed);
}

[Test]
hover_spells_a_private_type_as_written() {
    var c = loaded(
        "private_type_hover", "import \"util\";\ntest(): int { var t = tally(); return t.n; }\n", "main.pep"
    );
    var text = c.document.text;
    var failed = Array<String>();
    var shown = hover_text(c, at(text, "tally", 1));
    check(failed, "signature", shown.contains("tally(): Tally`"), shown);
    check(failed, "doc", shown.contains("ask jane@corp.com."), shown);
    check(failed, "one @", shown.split("@").count == 2, shown);
    all_passed(failed);
}

[Test]
hover_on_a_mangled_own_struct_shows_its_own_docs() {
    var main = "## My own error.\nstruct Error { var x: int; }\ntest(): int { var e = Error(); return e.x; }\n";
    var c = loaded("own_mangled_struct", main, "main.pep");
    var shown = hover_text(c, at(c.document.text, "Error()", 1));
    var failed = Array<String>();
    check(failed, "docs", shown.contains("My own error."), shown);
    all_passed(failed);
}

[Test]
a_local_hides_a_qualifier() {
    var main = "import geometry as g;\ntest(): int {\n    var g = 7;\n    return g;\n}\n";
    var c = loaded("local_hides", main, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var use = at(text, "return g", 7);
    check(failed, "hover", hover_text(c, use) == "`g` — `int`", hover_text(c, use));
    check(failed, "file", def_file(c, use) == "pep-lsp-test-local_hides/main.pep", def_file(c, use));
    all_passed(failed);
}

const DOCUMENTED = "## A counter.\nstruct Counter {\n    ## How many so far.\n    var count: int;\n\n    ## Adds `by` to the count.\n    ##\n    ## @param by the amount to add\n    ## @returns the new count\n    add(by: int): int {\n        count = count + by;\n        return count;\n    }\n}\n\n## Doubles `x`.\n##\n## @param x the value\n## @returns twice `x`\ndouble_it(x: int): int { return x * 2; }\n\ntest(): int {\n    var c: Counter = Counter();\n    c.add(1);\n    return double_it(c.count);\n}\n";

[Test]
hover_shows_doc_comments() {
    var c = loaded("docs", DOCUMENTED, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var call = hover_text(c, at(text, "double_it(c", 1));
    check(failed, "call doc", call.contains("Doubles `x`."), call);
    check(failed, "call params", call.contains("**Parameters**\n- `x` — the value"), call);
    check(failed, "call returns", call.contains("**Returns**\n- twice `x`"), call);
    var method = hover_text(c, at(text, "c.add", 3));
    check(failed, "method", method.contains("Adds `by` to the count."), method);
    var field = hover_text(c, at(text, "c.count", 3));
    check(failed, "field", field.contains("How many so far."), field);
    all_passed(failed);
}

const FRESH = "make(name: String): Array<String> {\n    var list = Array<String>();\n    list.append(name + \"!\");\n    return list;\n}\n\nsame(list: Array<String>): Array<String> {\n    return list;\n}\n\nmain(): int {\n    var a = make(\"x\");\n    var b = same(a);\n    return 0;\n}\n";

[Test]
hover_says_when_a_function_returns_a_fresh_value() {
    var c = loaded("fresh", FRESH, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var made = hover_text(c, at(text, "make(\"x\")", 0));
    check(failed, "make", made.contains("Returns a fresh value"), made);
    var same = hover_text(c, at(text, "same(a)", 0));
    check(failed, "same", !same.contains("Returns a fresh value"), same);
    all_passed(failed);
}

const OVERLOADED = "## Scales a whole number.\nscale(x: int): int { return x * 2; }\n## Scales a fraction.\nscale(x: double): double { return x * 3.0; }\nscale(s: String): int { return 0; }\n\nmain(): int {\n    var a = scale(2.5);\n    var f: (int) => int = scale;\n    return scale(4) + f(1);\n}\n";

[Test]
hover_on_an_overloaded_call_shows_the_chosen_member() {
    var c = loaded("overloads", OVERLOADED, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var fraction = hover_text(c, at(text, "scale(2.5)", 1));
    check(failed, "fraction", fraction.starts_with("`scale` — `scale(x: double): double` (+2 overloads)"), fraction);
    check(failed, "fraction doc", fraction.contains("Scales a fraction."), fraction);
    var whole = hover_text(c, at(text, "scale(4)", 0));
    check(failed, "whole", whole.contains("scale(x: int): int") and whole.contains("Scales a whole number."), whole);
    var value = hover_text(c, at(text, "int = scale", 7));
    check(failed, "value", value.contains("scale(x: int): int"), value);
    all_passed(failed);
}

[Test]
definition_of_an_overloaded_call_is_the_chosen_member() {
    var c = loaded("overload_definition", OVERLOADED, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var fraction = def_rest(c, at(text, "scale(2.5)", 2));
    check(failed, "fraction", fraction.starts_with("scale(x: double)"), fraction);
    var whole = def_rest(c, at(text, "scale(4)", 2));
    check(failed, "whole", whole.starts_with("scale(x: int)"), whole);
    all_passed(failed);
}

[Test]
definition_after_an_edit_reads_the_last_passed_analysis() {
    var uri = tree("stale_overload", OVERLOADED, "main.pep");
    var text = OVERLOADED;
    var ready = analyze(uri, text);
    expect_equal(outcome_of(ready), "passed");
    var some = Optional<Analysis>.Value(ready);
    var failed = Array<String>();
    var edited = "# A note.\n" + text;
    var document = lsp.TextDocument(uri, edited);
    var starts = (offset: ulong) => {
        var found = definition_across_edits(document, some, some, offset);
        if (found.count == 0) {
            return "<none>";
        }
        var start = document.offset_at(found[0].range.start);
        return edited.substr_bytes(start, edited.size - start);
    };
    var fraction = starts(at(edited, "scale(2.5)", 2));
    check(failed, "fraction", fraction.starts_with("scale(x: double)"), fraction);
    var whole = starts(at(edited, "scale(4)", 2));
    check(failed, "whole", whole.starts_with("scale(x: int)"), whole);
    var hover = hover_across_edits(document, some, some, at(edited, "scale(2.5)", 1));
    var shown = hover.is_empty() ? "<none>" : hover.value().contents.value;
    check(failed, "stale hover doc", shown.contains("Scales a fraction"), shown);
    check(failed, "stale hover note", shown.contains("Checking your latest edit"), shown);
    # Once the edit checks, the note goes.
    var checked = Optional<Analysis>.Value(analyze(uri, edited));
    hover = hover_across_edits(document, checked, checked, at(edited, "scale(2.5)", 1));
    shown = hover.is_empty() ? "<none>" : hover.value().contents.value;
    check(failed, "checked hover", !shown.contains("latest edit") and shown != "<none>", shown);
    # An edit that does not parse is checked, and the note says it fails.
    var broken = edited + "\nmain(: int {";
    var latest = Optional<Analysis>.Value(analyze(uri, broken));
    hover = hover_across_edits(lsp.TextDocument(uri, broken), latest, checked, at(broken, "scale(2.5)", 1));
    shown = hover.is_empty() ? "<none>" : hover.value().contents.value;
    check(failed, "broken hover", shown.contains("does not check yet"), shown);
    all_passed(failed);
}

const COLORS = "## A traffic light color.\nenum Color {\n    ## Stop.\n    Red,\n    Amber,\n    Green,\n}\n\nscore(c: Color): int {\n    match (c) {\n        Red => { return 1; }\n    }\n    return 0;\n}\n\ntest(): int { return score(Color.Amber); }\n";

[Test]
hover_on_an_enum_case_shows_its_value_and_docs() {
    var complete = COLORS.replace("Red => { return 1; }", "Red => { return 1; }\n        else => { return 2; }");
    var c = loaded("enum_hover", complete, "main.pep");
    var failed = Array<String>();
    var value = hover_text(c, at(complete, "Color.Amber", 7));
    check(failed, "value", value.contains("Color.Amber = 1"), value);
    # While the program does not build, the case without its value.
    c = loaded_anyway("enum_hover_broken", COLORS, "main.pep");
    value = hover_text(c, at(COLORS, "Color.Amber", 7));
    check(failed, "broken case", value.contains("Color.Amber"), value);
    var name = hover_text(c, at(COLORS, "Color.Amber", 1));
    check(failed, "broken enum doc", name.contains("A traffic light color."), name);
    all_passed(failed);
}

const SHAPES = "## A shape to draw.\nenum Shape {\n    ## A circle.\n    Circle(radius: int),\n    Rect(width: int, height: int),\n    Empty,\n}\n\narea(s: Shape): int {\n    match (s) {\n        Empty => { return 0; }\n    }\n    return 0;\n}\n\ntest(): int { return area(Shape.Rect(2, 3)); }\n";

[Test]
hover_and_completion_show_the_values_a_case_carries() {
    var complete = SHAPES.replace("Empty => { return 0; }", "Empty => { return 0; }\n        else => { return 1; }");
    var c = loaded("payload_hover", complete, "main.pep");
    var failed = Array<String>();
    var shown = hover_text(c, at(complete, "Shape.Rect", 7));
    check(failed, "built", shown.contains("Shape.Rect(width: int, height: int)"), shown);
    c = loaded_anyway("payload_hover_broken", SHAPES, "main.pep");
    shown = hover_text(c, at(SHAPES, "Shape.Rect", 7));
    check(failed, "broken", shown.contains("Shape.Rect(width: int, height: int)"), shown);
    # Completion after the enum's name, inside a call's arguments.
    var text = SHAPES.replace("Shape.Rect(2, 3)", "Shape.");
    var none = Optional<Analysis>.Empty;
    var items = completion_at(lsp.TextDocument("file:///nowhere/a.pep", text), none, none, at(text, "Shape.)", 6));
    var listed = ", ".join(labels(items));
    check(failed, "completion", listed == "Circle, Rect, Empty", listed);
    var detail = items.count == 0 ? "<none>" : items[0].detail.value();
    check(failed, "completion detail", detail == "Shape.Circle(radius: int)", detail);
    all_passed(failed);
}

[Test]
a_match_missing_cases_with_values_binds_them() {
    var analysis = analyze(temp_file("payload_missing_arms.pep", SHAPES), SHAPES);
    expect_equal(
        actions_at(analysis, 9, 6),
        "Add the missing cases of 'Shape' [11:0-11:0         Circle(radius) => {}\n        Rect(width, height) => {}\n]"
    );
}

const OVERLOADED_METHODS = "struct Meter {\n    var n: int;\n    ## Adds a whole number.\n    add(x: int): int { return n + x; }\n    ## Adds a fraction.\n    add(x: double): double { return 0.5; }\n}\n\nmain(): int {\n    var m = Meter();\n    var a = m.add(2.5);\n    return m.add(1);\n}\n";

[Test]
hover_and_definition_of_an_overloaded_method_call() {
    var c = loaded("method_overloads", OVERLOADED_METHODS, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var fraction = hover_text(c, at(text, "add(2.5)", 1));
    check(failed, "hover", fraction.starts_with("`add` — `add(x: double): double` (+1 overload)"), fraction);
    check(failed, "hover doc", fraction.contains("Adds a fraction."), fraction);
    var rest = def_rest(c, at(text, "add(1)", 1));
    check(failed, "definition", rest.starts_with("add(x: int)"), rest);
    all_passed(failed);
}

const CONSTRAINED = "trait Shape {\n    area(): int;\n}\n\nstruct Circle {\n    area(): int { return 3; }\n}\n\nstruct Gallery<T: Shape> {\n    var items = Array<T>();\n}\n\ntotal<T: Shape>(items: Array<T>): int { return 0; }\n\nwrap<T>(item: T): Gallery<T> { return Gallery<T>(); }\n\nmain(): int {\n    return total(Array<Circle>());\n}\n";

[Test]
hover_shows_generic_constraints() {
    var c = loaded_anyway("constraints_hover", CONSTRAINED, "main.pep");
    var failed = Array<String>();
    var total = hover_text(c, at(CONSTRAINED, "total(Array", 0));
    check(failed, "hover", total.contains("total<T: Shape>(items: Array<T>): int"), total);
    all_passed(failed);
}

# The messages of `analysis`'s diagnostics, joined.
messages(analysis: Analysis): String {
    var out = Array<String>();
    for (var d in analysis.diagnostics) {
        out.append(d.message);
    }
    return " | ".join(out);
}

[Test]
an_unconstrained_parameter_offers_to_constrain_it() {
    var analysis = analyze(tree("constraints_fix", CONSTRAINED, "main.pep"), CONSTRAINED);
    var failed = Array<String>();
    var shown = messages(analysis);
    check(failed, "diagnostic", shown == "'T' does not conform to trait 'Shape', required by 'T' in 'Gallery'", shown);
    var actions = actions_at(analysis, 14, 26);
    check(failed, "action", actions == "Constrain 'T' to 'Shape' [14:6-14:6 : Shape]", actions);
    all_passed(failed);
}

[Test]
a_type_that_does_not_conform_offers_the_extension() {
    var main = CONSTRAINED.replace("wrap<T>", "wrap<T: Shape>");
    var analysis = analyze(tree("constraints_extend", main, "main.pep"), main);
    var failed = Array<String>();
    var shown = messages(analysis);
    check(
        failed, "diagnostic", shown == "'Circle' does not conform to trait 'Shape', required by 'T' in 'total'", shown
    );
    var actions = actions_at(analysis, 17, 17);
    check(
        failed,
        "action",
        actions == "Declare 'extend Circle with Shape' [6:1-6:1 \n\nextend Circle with Shape {\n}]",
        actions
    );
    all_passed(failed);
}

const NOT_COPYABLE = "struct Handle {\n    var fd: int;\n    destruct {\n        fd = -1;\n    }\n}\n\nmain(): int {\n    var h = Handle();\n    var c = copy(h);\n    return 0;\n}\n";

[Test]
cannot_copy_offers_a_copyable_skeleton() {
    var analysis = analyze(tree("not_copyable", NOT_COPYABLE, "main.pep"), NOT_COPYABLE);
    var failed = Array<String>();
    var shown = messages(analysis);
    check(failed, "diagnostic", shown == "cannot copy 'Handle', which is not trivially copyable", shown);
    var actions = actions_at(analysis, 9, 13);
    check(
        failed,
        "action",
        actions.starts_with(
            "Implement Copyable<Handle> [5:1-5:1 \n\nextend Handle with Copyable<Handle> {\n    copy(): Handle {"
        ),
        actions
    );
    all_passed(failed);
}

const NESTED = "import geometry as g;\nstruct Inner {\n    var z: int;\n    twice(): int { return z * 2; }\n}\nstruct Outer { var y: Inner; }\nstruct Top {\n    var o: Outer;\n    f(): int { return this.o.y.z; }\n}\nmain(): int {\n    var x = Outer();\n    var w: Outer = Outer();\n    var p = g.make(1, 2);\n    return x.y.z + w.y.twice() + p.y;\n}\n";

[Test]
definition_of_a_nested_member() {
    var c = loaded("nested_member", NESTED, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var expect_rest = (label: String, offset: ulong, starts: String) => {
        var rest = def_rest(c, offset);
        check(failed, label, rest.starts_with(starts), rest);
    };
    expect_rest("this.o", at(text, "o.y.z", 0), "o: Outer");
    expect_rest("this.o.y", at(text, "y.z;", 0), "y: Inner");
    expect_rest("this.o.y.z", at(text, "z;", 0), "z: int");
    expect_rest("x", at(text, "x.y.z", 0), "x = Outer");
    expect_rest("x.y", at(text, "y.z +", 0), "y: Inner");
    expect_rest("x.y.z", at(text, "z +", 0), "z: int");
    expect_rest("w.y.twice", at_nth(text, "twice()", 1, 1), "twice(): int");
    var py = at(text, "p.y", 2);
    check(failed, "p.y file", def_file(c, py) == "geometry/module.pep", def_file(c, py));
    expect_rest("p.y", py, "y: int");
    all_passed(failed);
}

const SYNTHESIZED = "struct Money {\n    var cents: int;\n    +(other: Money): Money { var m = Money(); m.cents = cents + other.cents; return m; }\n}\nmain(): int {\n    var xs = [1, 2];\n    var i = 0;\n    var total = xs[i];\n    for (var v in xs) { total = total + v; }\n    var a = Money();\n    var b = a + a;\n    var c = b.cents > 0 ? 1 : 2;\n    var d = (a + b).cents;\n    var f = (): int => { return b.cents; };\n    return total + b.cents + c + d + f();\n}\n";

[Test]
definition_inside_a_synthesized_call_is_the_name() {
    var c = loaded("synthesized", SYNTHESIZED, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var expect_rest = (needle: String, starts: String) => {
        var rest = def_rest(c, at(text, needle, 0));
        check(failed, needle, rest.starts_with(starts), rest);
    };
    expect_rest("xs[i]", "xs = [1");
    expect_rest("i];", "i = 0");
    expect_rest("xs) {", "xs = [1");
    expect_rest("a + a", "a = Money");
    expect_rest("a;\n", "a = Money");
    expect_rest("cents;", "cents: int");
    expect_rest("b.cents > 0", "b = a");
    expect_rest("a + b)", "a = Money");
    var captured = at(text, "b.cents; }", 0);
    var found = definition_at(c, captured);
    if (found.count > 0) {
        var start = c.document.offset_at(found[0].range.start);
        check(failed, "captured is not its own use", start != captured, def_rest(c, captured));
    }
    all_passed(failed);
}

const ASSIGNED = "struct Core { var n: int; }\nstruct Task {\n    ## What the scheduler knows about the task.\n    var core: Core;\n    construct(start: Core) {\n        this.core = start;\n    }\n    swap(other: Core): int {\n        this.core = other;\n        return other.n;\n    }\n}\nextend Task {\n    bump(by: int): int {\n        var total = by + this.core.n;\n        return total;\n    }\n}\n";

[Test]
hover_on_parameters_and_assigned_fields() {
    var c = loaded("assigned_hover", ASSIGNED, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var field = hover_text(c, at(text, "core = start", 1));
    check(failed, "assigned field", field.contains("`.core` — `Core`") and field.contains("scheduler knows"), field);
    var start = hover_text(c, at(text, "start;", 1));
    check(failed, "start", start.contains("`start` — `Core`"), start);
    var other = hover_text(c, at(text, "other.n", 1));
    check(failed, "other", other.contains("`other` — `Core`"), other);
    var by = hover_text(c, at(text, "by + this", 0));
    check(failed, "by", by.contains("`by` — `int`"), by);
    var core = hover_text(c, at(text, "core.n;", 1));
    check(failed, "core in extension", core.contains("`.core` — `Core`") and core.contains("scheduler knows"), core);
    var rest = def_rest(c, at(text, "start;", 1));
    check(failed, "start definition", rest.starts_with("start: Core"), rest);
    rest = def_rest(c, at(text, "total;", 1));
    check(failed, "total definition", rest.starts_with("total = by"), rest);
    all_passed(failed);
}

const EXTENSIONS = "struct Point {\n    var x: int;\n    ## Spells the point.\n    to_string(): String { return \"p\"; }\n}\nextend Point {\n    describe(): String { return to_string(); }\n}\nextend Array<int> {\n    total(): int { return 0; }\n}\n";

[Test]
extension_members_and_arguments() {
    var c = loaded("extension_members", EXTENSIONS, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var call = at(text, "to_string();", 1);
    check(failed, "file", def_file(c, call) == "pep-lsp-test-extension_members/main.pep", def_file(c, call));
    check(failed, "rest", def_rest(c, call).starts_with("to_string(): String"), def_rest(c, call));
    check(failed, "hover", hover_text(c, call).contains("Spells the point"), hover_text(c, call));
    var int = hover_text(c, at(text, "int {", 1));
    check(failed, "int", !int.contains("type parameter"), int);
    all_passed(failed);
}

const MATCHED = "enum Found {\n    Hit(hash: int),\n    Miss,\n}\nlook(f: Found): int {\n    match (f) {\n        Hit(hash) => { return hash; }\n        Miss => { return 0; }\n    }\n    return 0;\n}\nconst doubled = (hash: int): int => hash * 2;\n";

# The Rust fixture names the closure `double`; the self-hosted compiler
# then resolves the runtime's `double` type to it, so it is `doubled` here.
# A closure constant is not thread-safe, so the analysis does not pass;
# the Rust test loaded it leniently.
[Test]
a_match_binding_is_local() {
    var c = loaded_anyway("match_binding", MATCHED, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var own = "pep-lsp-test-match_binding/main.pep";
    var bound = at(text, "hash; }", 1);
    check(failed, "binding file", def_file(c, bound) == own, def_file(c, bound));
    check(failed, "binding rest", def_rest(c, bound).starts_with("hash) =>"), def_rest(c, bound));
    var parameter = at(text, "hash * 2", 1);
    check(failed, "closure file", def_file(c, parameter) == own, def_file(c, parameter));
    check(failed, "closure rest", def_rest(c, parameter).starts_with("hash: int)"), def_rest(c, parameter));
    all_passed(failed);
}

const TRAIT_CALL = "trait Driver {\n    ## Waits for events, at most `timeout` milliseconds.\n    poll(timeout: int): bool;\n}\nstruct Quiet { poll(timeout: int): bool { return false; } }\nextend Quiet with Driver;\nstruct Worker {\n    var driver: Driver;\n    tick(): bool { return this.driver.poll(5); }\n}\n";

[Test]
hover_on_a_trait_method_call() {
    var c = loaded("trait_call", TRAIT_CALL, "main.pep");
    var failed = Array<String>();
    var shown = hover_text(c, at(c.document.text, "poll(5)", 1));
    check(failed, "hover", shown.contains("poll(timeout: int): bool") and shown.contains("Waits for events"), shown);
    all_passed(failed);
}

const MATCHED_SHAPES = "enum Shape {\n    Circle(radius: int),\n    Rect(width: int, height: int),\n    Point,\n}\n\nenum List {\n    Empty,\n    Cons(head: int, tail: List),\n}\n\narea(s: Shape): int {\n    return match (s) {\n        Circle(r) => 3 * r * r,\n        Rect(w, h) => w * h,\n        Point => 0,\n    };\n}\n\nsum(list: List): int {\n    var total = 0;\n    var rest = list;\n    while (rest is Cons(head, tail)) {\n        total += head;\n        rest = tail;\n    }\n    return total;\n}\n";

[Test]
match_patterns_and_their_bindings() {
    var c = loaded("match_patterns", MATCHED_SHAPES, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var circle = at(text, "Circle(r)", 0);
    var h = hover_text(c, circle);
    check(failed, "case hover", h.starts_with("`Circle` — `Shape.Circle(radius: int)`"), h);
    check(failed, "case definition", def_rest(c, circle).starts_with("Circle(radius"), def_rest(c, circle));
    var labels = ["bound r", "r * r", "* r"];
    var offsets = [at(text, "Circle(r)", 7), at(text, "r * r", 0), at(text, "* r,", 2)];
    var i: ulong = 0;
    while (i < 3) {
        h = hover_text(c, offsets[i]);
        check(failed, labels[i] + " hover", h.starts_with("`r` — `int`"), h);
        check(failed, labels[i] + " definition", def_rest(c, offsets[i]).starts_with("r) =>"), def_rest(c, offsets[i]));
        i = i + 1;
    }
    h = hover_text(c, at(text, "w * h", 0));
    check(failed, "w hover", h.starts_with("`w` — `int`"), h);
    var point = at(text, "Point =>", 0);
    check(failed, "Point definition", def_rest(c, point).starts_with("Point,"), def_rest(c, point));
    var cons = at(text, "Cons(head, tail)", 0);
    check(failed, "is case definition", def_rest(c, cons).starts_with("Cons(head: int"), def_rest(c, cons));
    h = hover_text(c, at(text, "tail))", 0));
    check(failed, "is tail hover", h.starts_with("`tail` — `List`"), h);
    h = hover_text(c, at(text, "= tail;", 2));
    check(failed, "used tail hover", h.starts_with("`tail` — `List`"), h);
    var head = at(text, "+= head", 3);
    check(failed, "used head definition", def_rest(c, head).starts_with("head, tail)"), def_rest(c, head));
    all_passed(failed);
}

[Test]
nested_patterns_and_their_bindings() {
    var source = MATCHED_SHAPES
        + "second(list: List): int {\n    return match (list) {\n        Cons(_, Cons(next, _)) => next,\n        else => 0,\n    };\n}\n";
    var c = loaded("nested_patterns", source, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var nested = at(text, "Cons(next", 0);
    check(failed, "nested case", def_rest(c, nested).starts_with("Cons(head: int"), def_rest(c, nested));
    var h = hover_text(c, at(text, "next, _", 0));
    check(failed, "bound next", h.starts_with("`next` — `int`"), h);
    h = hover_text(c, at(text, "=> next", 3));
    check(failed, "used next", h.starts_with("`next` — `int`"), h);
    all_passed(failed);
}

[Test]
enum_case_values_where_they_are_declared() {
    var c = loaded("enum_case_values", MATCHED_SHAPES, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var h = hover_text(c, at(text, "radius", 0));
    check(failed, "radius hover", h.starts_with("`radius` — `int`"), h);
    var height = at(text, "height", 0);
    check(failed, "height definition", def_rest(c, height).starts_with("height: int"), def_rest(c, height));
    var list = at(text, "tail: List", 6);
    check(failed, "List definition", def_rest(c, list).starts_with("List {"), def_rest(c, list));
    all_passed(failed);
}

const UNINSTANTIATED = "struct Box<T> {\n    var value: T;\n    construct(value: T) { this.value = value; }\n    get(): T { return value; }\n    static make(value: T): Box<T> { return Box<T>(value); }\n}\n\nstruct Holder {\n    var sizes: Array<int>;\n    construct() { sizes = Array<int>(); }\n\n    # Nothing calls this, so sema never checks its body.\n    first<T>(box: Box<T>): T {\n        var copy = Box<T>.make(box.get());\n        var inner = copy.get();\n        var count = sizes.count;\n        var (a, b) = (count, inner);\n        return copy.get<T>();\n    }\n}\n";

[Test]
a_generic_body_nothing_instantiates() {
    var c = loaded("uninstantiated", UNINSTANTIATED, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var h = hover_text(c, at(text, "var copy", 4));
    check(failed, "copy", h.starts_with("`copy` — `Box<T>`"), h);
    var make = at(text, ".make(box", 1);
    h = hover_text(c, make);
    check(failed, "make hover", h.starts_with("`make` — `static make(value: T): Box<T>`"), h);
    check(failed, "make definition", def_rest(c, make).starts_with("make(value"), def_rest(c, make));
    h = hover_text(c, at(text, "inner", 0));
    check(failed, "inner", h.starts_with("`inner` — `T`"), h);
    var get = at(text, "copy.get()", 5);
    check(failed, "get definition", def_rest(c, get).starts_with("get(): T"), def_rest(c, get));
    var count = at(text, "sizes.count", 6);
    check(failed, "count file", def_file(c, count) == "runtime/array.pep", def_file(c, count));
    check(failed, "count rest", def_rest(c, count).starts_with("count: ulong"), def_rest(c, count));
    h = hover_text(c, at(text, "count = ", 0));
    check(failed, "count local", h.starts_with("`count` — `ulong`"), h);
    h = hover_text(c, at(text, "var (a, b)", 8));
    check(failed, "b", h.starts_with("`b` — `T`"), h);
    var t = at(text, "get<T>", 4);
    h = hover_text(c, t);
    check(failed, "T hover", h.starts_with("`T` — `type parameter`"), h);
    check(failed, "T definition", def_rest(c, t).starts_with("T>(box"), def_rest(c, t));
    all_passed(failed);
}

[Test]
tuple_labels() {
    var main = "position(): (line: int, column: int) {\n    return (line: 3, column: 7);\n}\n"
        + "test(): int {\n    var p = position();\n    return p.column;\n}\n";
    var c = loaded("tuple_labels", main, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var column = at(text, "p.column", 2);
    var h = hover_text(c, column);
    check(failed, "column hover", h.starts_with("`.column` — `int`"), h);
    check(failed, "column definition", def_rest(c, column).starts_with("column: int)"), def_rest(c, column));
    h = hover_text(c, at(text, "line: 3", 0));
    check(failed, "line label", h.starts_with("`line` — `int`"), h);
    all_passed(failed);
}

[Test]
lowered_calls_trait_defaults_and_bounds() {
    var main = "trait Named {\n    name(): String;\n    shout(): String { return name() + \"!\"; }\n}\n"
        + "struct Box<T> {\n    var item: T;\n    construct(item: T) { this.item = item; }\n}\n"
        + "extend Box<T: Named> {\n    label(): String { return item.name(); }\n}\n"
        + "test(): String {\n    var a = 2;\n    return String.format(\"{1} {0}\", a, \"x\");\n}\n";
    var c = loaded("lowered_calls", main, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var name = at(text, "name() +", 0);
    check(failed, "trait default", def_rest(c, name).starts_with("name(): String;"), def_rest(c, name));
    var item = at(text, "item.name", 5);
    check(failed, "bound", def_rest(c, item).starts_with("name(): String;"), def_rest(c, item));
    var h = hover_text(c, at(text, "format(", 0));
    check(failed, "format hover", h.starts_with("`format` — `static format("), h);
    var string = at(text, "String.format", 0);
    check(failed, "String file", def_file(c, string) == "runtime/string.pep", def_file(c, string));
    h = hover_text(c, at(text, ", a,", 2));
    check(failed, "argument", h.starts_with("`a` — `int`"), h);
    all_passed(failed);
}

[Test]
a_closure_parameter_shadowing_its_receiver() {
    var main = "struct Node {\n    visit(f: (Node) => void) { f(this); }\n}\n"
        + "walk<T>(node: Node) {\n    node.visit((node) => { var inner = node; });\n}\n";
    var c = loaded("closure_shadowing", main, "main.pep");
    var failed = Array<String>();
    var h = hover_text(c, at(c.document.text, "(node) =>", 1));
    check(failed, "hover", h.starts_with("`node` — `Node`"), h);
    all_passed(failed);
}

[Test]
property_accessor_bodies_resolve() {
    var main = "struct Account {\n    var _cents: long;\n    var dollars: long {\n        get {\n"
        + "            var whole = _cents;\n            return whole / 100;\n        }\n        set {\n"
        + "            _cents = value * 100;\n        }\n    }\n}\n"
        + "test(): int {\n    var a = Account();\n    a.dollars = 3;\n    return a.dollars as int;\n}\n";
    var c = loaded("property_accessors", main, "main.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var h = hover_text(c, at(text, "whole /", 0));
    check(failed, "whole", h.starts_with("`whole` — `long`"), h);
    var cents = at(text, "_cents;", 0);
    check(failed, "_cents", def_rest(c, cents).starts_with("_cents: long"), def_rest(c, cents));
    h = hover_text(c, at(text, "value *", 0));
    check(failed, "value", h.starts_with("`value` — `long`"), h);
    var dollars = at(text, "dollars as", 0);
    check(failed, "dollars", def_rest(c, dollars).starts_with("dollars: long"), def_rest(c, dollars));
    all_passed(failed);
}

[Test]
a_module_file_reaches_its_modules_other_files() {
    var c = loaded("module_mates", "", "deps/geometry/shapes.pep");
    var text = c.document.text;
    var failed = Array<String>();
    var make = at(text, "make(", 0);
    check(failed, "make hover", hover_text(c, make).contains("make(x: int, y: int): Point"), hover_text(c, make));
    check(failed, "make file", def_file(c, make) == "geometry/module.pep", def_file(c, make));
    var half = at(text, "half(", 0);
    var h = hover_text(c, half);
    check(failed, "half hover", h.contains("half(x: int): int") and h.contains("Half of"), h);
    check(failed, "half file", def_file(c, half) == "geometry/module.pep", def_file(c, half));
    check(failed, "half rest", def_rest(c, half).starts_with("half(x: int)"), def_rest(c, half));
    var names = Array<String>();
    if (c.program is Value(program)) {
        for (var symbol in module_globals(program)) {
            names.append(symbol.name);
        }
    }
    check(failed, "module globals", names.contains("half") and names.contains("Point"), ", ".join(names));
    all_passed(failed);
}

[Test]
a_name_after_a_non_ascii_character_does_not_panic() {
    var text = "#─String.format\n#─Color.";
    var module = parse.parse(text).value();
    var context = Context(lsp.TextDocument("file:///nowhere/a.pep", text), module);
    var offset = at(text, "String", 1);
    expect_equal(hover_text(context, offset), "");
    expect_equal(definition_at(context, offset).count, 0 as ulong);
    expect_true(enum_cases_before(module, Optional<link.Program>.Empty, text, text.size).is_empty());
    var none = Optional<Analysis>.Empty;
    completion_at(lsp.TextDocument("file:///nowhere/a.pep", text), none, none, text.size);
    completion_at(lsp.TextDocument("file:///nowhere/a.pep", text), none, none, offset);
}

# Writes `text` to `name` in the emptied temporary folder for `test`;
# returns its URI.
fresh_file(test: String, name: String, text: String): String {
    Directory.remove_all(Directory.temp().join(Path($"pep-lsp-test-{test}")));
    return temp_file_in(test, name, text);
}

# The line of the first definition at `offset` in the analysis of `text`
# as `uri`; -1 when there is none.
definition_line(uri: String, text: String, offset: ulong): int {
    var found = definition_at(analyzed(uri, text), offset);
    return found.count == 0 ? -1 : found[0].range.start.line;
}

[Test]
a_changed_import_refreshes_the_analysis() {
    # The build cache keeps each checked layer; a file an import reaches
    # that changes on disk is read again, though the document is the same.
    var test = "changed_import";
    var text = "import \"util\";\nmain(): int { return twice(2); }\n";
    var uri = fresh_file(test, "main.pep", text);
    var twice = "export twice(x: int): int { return x * 2; }\n";
    temp_file_in(test, "util.pep", twice);
    var call = at(text, "twice(2)", 1);
    expect_equal(definition_line(uri, text, call), 0);
    temp_file_in(test, "util.pep", "# Moved down a line.\n" + twice);
    expect_equal(definition_line(uri, text, call), 1);
}

[Test]
fixing_an_import_that_did_not_load_refreshes_the_analysis() {
    var test = "failed_import";
    var text = "import \"broken\";\nmain(): int { return f(); }\n";
    var uri = fresh_file(test, "main.pep", text);
    # Not there yet, then not parsing: the analysis does not pass, and
    # passes once the file is fixed.
    expect_true(analyze(uri, text).outcome != "passed");
    temp_file_in(test, "broken.pep", "export f(): int { return 1 + ; }\n");
    expect_true(analyze(uri, text).outcome != "passed");
    temp_file_in(test, "broken.pep", "export f(): int { return 1; }\n# Fixed.\n");
    expect_equal(outcome_of(analyze(uri, text)), "passed");
}

[Test]
arguments_start_the_server_or_answer_without_it() {
    expect_true(handle_arguments(["pep-lsp"]).is_empty());
    expect_true(handle_arguments(["pep-lsp", "--stdio"]).is_empty());
    expect_equal(handle_arguments(["pep-lsp", "--version"]).value(), 0);
    expect_equal(handle_arguments(["pep-lsp", "--help"]).value(), 0);
    expect_equal(handle_arguments(["pep-lsp", "--port", "9000"]).value(), 2);
}

# How deep the Rust parser let source nest (`MAX_NESTING`, 256), less the
# levels the wrapper adds.
const DEEPEST: ulong = 252;

# A program whose `main` runs `body`.
deepest_program(body: String): String {
    return "f(x: int): int { return x; }\nexport main(): int {\n    var x = 1;\n" + body + "\n    return x;\n}\n";
}

[Test]
deepest_source_fits_the_server_stack() {
    # The server analyzes on a thread of its own, with the default stack:
    # a stack overflow cannot be caught, and ends the server.
    var n = DEEPEST;
    var programs = [
        deepest_program("    x = 1" + " + x".repeat(n) + ";"),
        deepest_program("    x = " + "(".repeat(n) + "x" + ")".repeat(n) + ";"),
        deepest_program("    x = " + "f(".repeat(n / 2) + "x" + ")".repeat(n / 2) + ";"),
        deepest_program("if (x == 1) {\n".repeat(n) + "x = 2;" + "}\n".repeat(n)),
        deepest_program("    if (x == 0) { x = 1; }" + " else if (x == 2) { x = 3; }".repeat(n / 2)),
        deepest_program("    x = " + "- ".repeat(n) + "x;"),
        deepest_program("    var s = \"a\"" + " + \"a\"".repeat(n) + ";"),
    ];
    var documents = Channel<String>();
    var outcomes = Channel<String>();
    for (var i in 0..programs.count) {
        documents.send(temp_file_in("deepest", "main.pep", programs[i]));
        documents.send(copy(programs[i]));
        Thread.spawn(() => {
            var uri = documents.receive().value();
            outcomes.send(copy(outcome_of(analyze(uri, documents.receive().value()))));
        }, "pep-lsp-analysis").join();
        expect_equal($"{i}: " + outcomes.receive().value(), $"{i}: passed");
    }
}
