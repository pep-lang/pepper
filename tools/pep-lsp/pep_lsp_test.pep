# pep-lsp's tests: the outline, analysis of documents on disk, and hover
# and go-to-definition.

import [Directory, File, Path] from io;
import json;
import [JsonValue] from json;
import compiler.link;
import lsp;
import compiler.parse;
import "actions";
import "analysis";
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
