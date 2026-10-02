//! Hover and go-to-definition through imports, on a file tree written to a
//! temp directory and loaded with the runtime, as the server loads it.

use super::*;
use pepper_sema::program::{Mode, Root, Setup, load_program};

/// A module, as in the driver's module tests: `module.pep` exports some of
/// its own declarations and re-exports from a file of the same module.
const GEOMETRY: &[(&str, &str)] = &[
    (
        "deps/geometry/module.pep",
        r#"import "shapes";

export struct Point { var x: int; var y: int; }
export make(x: int, y: int): Point {
    var p = Point();
    p.x = x;
    p.y = y;
    return p;
}
export area as rect_area;
export Box;
"#,
    ),
    (
        "deps/geometry/shapes.pep",
        r#"export area(w: int, h: int): int { return w * h; }
export struct Box<T> { var value: T; }
"#,
    ),
    ("deps/solids/module.pep", "export * from \"cube\";\nexport [volume as size] from \"cube\";\n"),
    ("deps/solids/cube.pep", "export volume(s: int): int { return s * s * s; }\nexport edge(s: int): int { return s; }\n"),
    ("util.pep", "export twice(x: int): int { return x * 2; }\nstruct Tally { var n: int; }\n## Counts; ask jane@corp.com.\nexport tally(): Tally { return Tally(); }\n"),
];

/// Write `GEOMETRY` plus `main` (as `main.pep`) under a fresh directory for
/// `test`, and load the program rooted at `root` (a path in the tree).
fn load(test: &str, main: &str, root: &str) -> (Url, String, Program) {
    // The process id keeps concurrent test runs on one machine (CI jobs
    // for several LLVM versions) from deleting each other's files.
    let dir = std::env::temp_dir().join(format!("pepper_lsp_{}_{}", test, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    for (path, text) in GEOMETRY.iter().chain(&[("main.pep", main)]) {
        let path = dir.join(path);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, text).unwrap();
        backdate(&path);
    }
    let path = dir.join(root);
    let uri = Url::from_file_path(&path).unwrap();
    let text = std::fs::read_to_string(&path).unwrap();
    let deps = [dir.join("deps")];
    let setup = Setup { import_dirs: &deps, mode: Mode::Lenient, ..Default::default() };
    let program = load_program(Root { name: uri.to_string(), source: text.clone(), path }, &setup).unwrap();
    (uri, text, program)
}

/// Set `path`'s modification time a minute back, as for a file saved before
/// the test: one saved as a program loads makes its analysis stale at once.
fn backdate(path: &std::path::Path) {
    let file = std::fs::File::options().write(true).open(path).unwrap();
    file.set_modified(std::time::SystemTime::now() - std::time::Duration::from_secs(60)).unwrap();
}

/// The byte offset of the `nth` (0-based) occurrence of `needle` in `text`,
/// plus `delta`.
fn at(text: &str, needle: &str, nth: usize, delta: usize) -> usize {
    text.match_indices(needle).nth(nth).unwrap_or_else(|| panic!("no {:?} #{}", needle, nth)).0 + delta
}

fn hover(uri: &Url, text: &str, program: &Program, offset: usize) -> String {
    match PepperLsp::hover_at(uri, text, Some(program), sema_model_of(program).ok().as_ref(), offset).map(|h| h.contents) {
        Some(HoverContents::Markup(m)) => m.value,
        other => panic!("no hover at {}: {:?}", offset, other),
    }
}

/// The definition at `offset`: the file it is in (folder and name) and the
/// text at its range's start.
fn definition(uri: &Url, text: &str, program: &Program, offset: usize) -> (String, String) {
    let locations = PepperLsp::definition_at(uri, text, Some(program), sema_model_of(program).ok().as_ref(), offset).expect("a definition");
    let loc = &locations[0];
    let path = loc.uri.to_file_path().unwrap();
    let source = std::fs::read_to_string(&path).unwrap();
    let line = source.lines().nth(loc.range.start.line as usize).unwrap_or("");
    (file_label(&path.to_string_lossy()), line[loc.range.start.character as usize..].to_string())
}

const ALIAS: &str = r#"import geometry as g;
test(): int {
    var p: g.Point = g.make(1, 2);
    var b = g.Box<int>();
    b.value = g.rect_area(2, 5);
    return p.y + b.value;
}
"#;

#[test]
fn qualified_function_leads_to_its_module_file() {
    let (uri, text, program) = load("qualified_fn", ALIAS, "main.pep");
    let make = at(&text, "g.make", 0, 3);
    let h = hover(&uri, &text, &program, make);
    assert!(h.contains("make(x: int, y: int): Point") && h.contains("geometry/module.pep"), "{}", h);
    let (file, rest) = definition(&uri, &text, &program, make);
    assert_eq!(file, "geometry/module.pep");
    assert!(rest.starts_with("make(x: int"), "{}", rest);
}

#[test]
fn qualified_reexport_leads_to_the_declaring_file() {
    let (uri, text, program) = load("qualified_reexport", ALIAS, "main.pep");
    let (file, rest) = definition(&uri, &text, &program, at(&text, "rect_area", 0, 0));
    assert_eq!(file, "geometry/shapes.pep");
    assert!(rest.starts_with("area(w: int"), "{}", rest);
}

#[test]
fn qualifier_leads_to_the_module() {
    let (uri, text, program) = load("qualifier", ALIAS, "main.pep");
    let q = at(&text, "g.make", 0, 0);
    assert!(hover(&uri, &text, &program, q).contains("geometry/module.pep"));
    assert_eq!(definition(&uri, &text, &program, q).0, "geometry/module.pep");
    // The module name in the import, too.
    assert_eq!(definition(&uri, &text, &program, at(&text, "geometry", 0, 1)).0, "geometry/module.pep");
}

#[test]
fn qualified_types_lead_to_their_declarations() {
    let (uri, text, program) = load("qualified_types", ALIAS, "main.pep");
    let point = at(&text, "g.Point", 0, 2);
    assert!(hover(&uri, &text, &program, point).contains("struct Point"));
    let (file, rest) = definition(&uri, &text, &program, point);
    assert_eq!(file, "geometry/module.pep");
    assert!(rest.starts_with("Point {"), "{}", rest);
    // A generic construction, re-exported from another file.
    let (file, rest) = definition(&uri, &text, &program, at(&text, "g.Box", 0, 3));
    assert_eq!(file, "geometry/shapes.pep");
    assert!(rest.starts_with("Box<T>"), "{}", rest);
}

#[test]
fn listed_symbols_and_aliases_lead_to_their_declarations() {
    let main = r#"import [make, Point as Pt, rect_area as area] from geometry;
test(): int {
    var p: Pt = make(2, 3);
    return area(p.x, p.y);
}
"#;
    let (uri, text, program) = load("listed", main, "main.pep");
    // A use of an alias, in a return statement.
    let use_ = at(&text, "area(p.x", 0, 0);
    let h = hover(&uri, &text, &program, use_);
    assert!(h.starts_with("`area` — `area(w: int, h: int): int`"), "{}", h);
    assert_eq!(definition(&uri, &text, &program, use_).0, "geometry/shapes.pep");
    // An aliased type, and a call in an initializer.
    assert!(definition(&uri, &text, &program, at(&text, "Pt =", 0, 0)).1.starts_with("Point {"));
    assert!(definition(&uri, &text, &program, at(&text, "make(2", 0, 0)).1.starts_with("make(x"));
    // The entries of the import list.
    assert!(definition(&uri, &text, &program, at(&text, "rect_area as", 0, 0)).1.starts_with("area(w"));
    assert!(definition(&uri, &text, &program, at(&text, "as Pt", 0, 3)).1.starts_with("Point {"));
}

#[test]
fn file_import_leads_to_the_file() {
    let main = "import \"util\";\ntest(): int { return twice(3); }\n";
    let (uri, text, program) = load("file_import", main, "main.pep");
    let (file, rest) = definition(&uri, &text, &program, at(&text, "twice", 0, 0));
    assert!(file.ends_with("/util.pep"), "{}", file);
    assert!(rest.starts_with("twice(x"), "{}", rest);
    assert!(definition(&uri, &text, &program, at(&text, "\"util\"", 0, 2)).0.ends_with("/util.pep"));
}

#[test]
fn reexport_leads_to_the_reexported_declaration() {
    let (uri, text, program) = load("reexport", "", "deps/geometry/module.pep");
    let (file, rest) = definition(&uri, &text, &program, at(&text, "export area", 0, 7));
    assert_eq!(file, "geometry/shapes.pep");
    assert!(rest.starts_with("area(w"), "{}", rest);
}

#[test]
fn export_from_leads_to_the_source_and_its_declarations() {
    let main = "import solids;\ntest(): int {\n    var e = solids.edge(2);\n    return e + solids.size(1);\n}\n";
    let (uri, text, program) = load("export_from_use", main, "main.pep");
    let (file, rest) = definition(&uri, &text, &program, at(&text, "edge", 0, 0));
    assert_eq!(file, "solids/cube.pep");
    assert!(rest.starts_with("edge(s"), "{}", rest);
    assert!(definition(&uri, &text, &program, at(&text, "size", 0, 0)).1.starts_with("volume(s"));

    let (uri, text, program) = load("export_from_lines", "", "deps/solids/module.pep");
    // The source of `export * from`, and an entry of `export [...] from`.
    assert_eq!(definition(&uri, &text, &program, at(&text, "\"cube\"", 0, 2)).0, "solids/cube.pep");
    let (file, rest) = definition(&uri, &text, &program, at(&text, "volume", 0, 0));
    assert_eq!(file, "solids/cube.pep");
    assert!(rest.starts_with("volume(s"), "{}", rest);
}

#[test]
fn prelude_function_leads_to_the_runtime() {
    let main = "test(): int { assert(true, \"ok\"); return 0; }\n";
    let (uri, text, program) = load("prelude", main, "main.pep");
    let (file, rest) = definition(&uri, &text, &program, at(&text, "assert", 0, 0));
    assert_eq!(file, "runtime/internals.pep");
    assert!(rest.starts_with("assert(condition"), "{}", rest);
}

#[test]
fn hover_spells_a_private_type_as_written() {
    // util's private `Tally` is mangled in the linked program.
    let main = "import \"util\";\ntest(): int { var t = tally(); return t.n; }\n";
    let (uri, text, program) = load("private_type_hover", main, "main.pep");
    let shown = hover(&uri, &text, &program, at(&text, "tally", 0, 1));
    assert!(shown.contains("tally(): Tally`"), "{}", shown);
    // The doc comment is shown as written.
    assert!(shown.contains("ask jane@corp.com."), "{}", shown);
    assert_eq!(shown.matches('@').count(), 1, "{}", shown);
}

#[test]
fn hover_on_a_mangled_own_struct_shows_its_own_docs() {
    // The runtime exports `Error`, so the document's own `Error` is mangled.
    let main = "## My own error.\nstruct Error { var x: int; }\ntest(): int { var e = Error(); return e.x; }\n";
    let (uri, text, program) = load("own_mangled_struct", main, "main.pep");
    let shown = hover(&uri, &text, &program, at(&text, "Error()", 0, 1));
    assert!(shown.contains("My own error."), "{}", shown);
}

#[test]
fn a_local_hides_a_qualifier() {
    let main = "import geometry as g;\ntest(): int {\n    var g = 7;\n    return g;\n}\n";
    let (uri, text, program) = load("local_hides", main, "main.pep");
    let use_ = at(&text, "return g", 0, 7);
    assert_eq!(hover(&uri, &text, &program, use_), "`g` — `int`");
    assert_eq!(definition(&uri, &text, &program, use_).0, file_label(&uri.to_file_path().unwrap().to_string_lossy()));
}

const DOCUMENTED: &str = r#"## A counter.
struct Counter {
    ## How many so far.
    int count;

    ## Adds `by` to the count.
    ##
    ## @param by the amount to add
    ## @returns the new count
    int add(int by) {
        count = count + by;
        return count;
    }
}

## Doubles `x`.
##
## @param x the value
## @returns twice `x`
double_it(x: int): int { return x * 2; }

test(): int {
    Counter c = Counter();
    c.add(1);
    return double_it(c.count);
}
"#;

#[test]
fn hover_shows_doc_comments() {
    let (uri, text, program) = load("docs", DOCUMENTED, "main.pep");
    let call = hover(&uri, &text, &program, at(&text, "double_it(c", 0, 1));
    assert!(call.contains("Doubles `x`."), "{}", call);
    assert!(call.contains("**Parameters**\n- `x` — the value"), "{}", call);
    assert!(call.contains("**Returns**\n- twice `x`"), "{}", call);
    let method = hover(&uri, &text, &program, at(&text, "c.add", 0, 3));
    assert!(method.contains("Adds `by` to the count."), "{}", method);
    let field = hover(&uri, &text, &program, at(&text, "c.count", 0, 3));
    assert!(field.contains("How many so far."), "{}", field);
}

#[test]
fn deprecated_new_offers_a_quick_fix() {
    let uri = Url::parse("file:///t.pep").unwrap();
    let text = "struct S {\n    int x;\n    new(this.x = 1) {}\n}\n";
    let fixes = |text: &str, range| quick_fixes(&uri, text, &document_warnings(text, None, None), range);
    let actions = fixes(text, Range::new(Position::new(2, 5), Position::new(2, 5)));
    let [CodeActionOrCommand::CodeAction(action)] = actions.as_slice() else { panic!("{actions:?}") };
    assert_eq!(action.title, "Replace `new` with `construct`");
    assert_eq!(action.kind, Some(CodeActionKind::QUICKFIX));
    let diagnostic = &action.diagnostics.as_ref().unwrap()[0];
    assert_eq!(diagnostic.severity, Some(DiagnosticSeverity::WARNING));
    assert_eq!(diagnostic.tags, Some(vec![DiagnosticTag::DEPRECATED]));
    let edits = &action.edit.as_ref().unwrap().changes.as_ref().unwrap()[&uri];
    assert_eq!(edits, &vec![TextEdit {
        range: Range::new(Position::new(2, 4), Position::new(2, 7)),
        new_text: "construct".to_string(),
    }]);
    // Nothing to fix away from the warning, or once it is fixed.
    assert!(fixes(text, Range::new(Position::new(0, 0), Position::new(0, 1))).is_empty());
    assert!(fixes(&text.replace("new(", "construct("), Range::new(Position::new(2, 5), Position::new(2, 5))).is_empty());
}

#[test]
fn missing_semicolon_offers_a_quick_fix() {
    let uri = Url::parse("file:///t.pep").unwrap();
    let text = "main(): int {\n    var total = 1\n    return total;\n}\n";
    let actions = quick_fixes(&uri, text, &document_warnings(text, None, None), Range::new(Position::new(1, 17), Position::new(1, 17)));
    let [CodeActionOrCommand::CodeAction(action)] = actions.as_slice() else { panic!("{actions:?}") };
    assert_eq!(action.title, "Insert ';'");
    assert_eq!(action.diagnostics.as_ref().unwrap()[0].severity, Some(DiagnosticSeverity::ERROR));
    let edits = &action.edit.as_ref().unwrap().changes.as_ref().unwrap()[&uri];
    assert_eq!(edits, &vec![TextEdit { range: Range::new(Position::new(1, 17), Position::new(1, 17)), new_text: ";".to_string() }]);
}

const DEPRECATED: &str = r#"struct Counter {
    int value;
    [Deprecated("use 'copy' instead", "copy")]
    clone(): Counter { return this; }
    copy(): Counter { return this; }
}
[Deprecated("use 'twice' instead", "twice")]
dup(x: int): int { return x * 2; }
twice(x: int): int { return x * 2; }
test(): int {
    var c = Counter();
    var d = c.clone();
    return dup(d.value);
}
"#;

#[test]
fn deprecated_declarations_offer_quick_fixes() {
    let (uri, text, program) = load("deprecated", DEPRECATED, "main.pep");
    let warnings = document_warnings(&text, Some(&program), sema_model_of(&program).ok().as_ref());
    let messages: Vec<&str> = warnings.iter().map(|w| w.message.as_str()).collect();
    assert_eq!(messages, ["'dup' is deprecated: use 'twice' instead", "'clone' is deprecated: use 'copy' instead"]);
    // The method, found by the sema model's types.
    let actions = quick_fixes(&uri, &text, &warnings, Range::new(Position::new(11, 16), Position::new(11, 16)));
    let [CodeActionOrCommand::CodeAction(action)] = actions.as_slice() else { panic!("{actions:?}") };
    assert_eq!(action.title, "Replace 'clone' with 'copy'");
    let diagnostic = &action.diagnostics.as_ref().unwrap()[0];
    assert_eq!(diagnostic.tags, Some(vec![DiagnosticTag::DEPRECATED]));
    let edits = &action.edit.as_ref().unwrap().changes.as_ref().unwrap()[&uri];
    assert_eq!(edits, &vec![TextEdit { range: Range::new(Position::new(11, 14), Position::new(11, 19)), new_text: "copy".to_string() }]);
    // The function, found on the linked AST.
    let actions = quick_fixes(&uri, &text, &warnings, Range::new(Position::new(12, 12), Position::new(12, 12)));
    let [CodeActionOrCommand::CodeAction(action)] = actions.as_slice() else { panic!("{actions:?}") };
    assert_eq!(action.title, "Replace 'dup' with 'twice'");
}

const SEND_NAMED: &str = r#"import async;

const lines = async.Channel<String>();

main(): int {
    var line = "hello";
    lines.send(line);
    return 0;
}
"#;

#[test]
fn sending_a_variable_offers_move_and_copy() {
    let (uri, text, program) = load("send_named", SEND_NAMED, "main.pep");
    let diagnostics = fixable_diagnostics(&text, Some(&program), Some(&sema_model_of(&program)));
    let [error] = diagnostics.as_slice() else { panic!("{diagnostics:?}") };
    assert!(error.message.starts_with("'line' is not a new value"), "{}", error.message);
    let actions = quick_fixes(&uri, &text, &diagnostics, Range::new(Position::new(6, 17), Position::new(6, 17)));
    let titles: Vec<String> = actions
        .iter()
        .map(|a| match a {
            CodeActionOrCommand::CodeAction(action) => action.title.clone(),
            other => panic!("{other:?}"),
        })
        .collect();
    assert_eq!(titles, ["Hand 'line' over with 'move(line)'", "Pass a copy with 'copy(line)'"]);
    let replacements: Vec<String> = actions
        .iter()
        .map(|a| {
            let CodeActionOrCommand::CodeAction(action) = a else { unreachable!() };
            let edits = &action.edit.as_ref().unwrap().changes.as_ref().unwrap()[&uri];
            assert_eq!(edits[0].range, Range::new(Position::new(6, 15), Position::new(6, 19)));
            edits[0].new_text.clone()
        })
        .collect();
    assert_eq!(replacements, ["move(line)", "copy(line)"]);
}

const NOT_COPYABLE: &str = r#"struct Handle {
    int fd;
    destruct {
        fd = -1;
    }
}

main(): int {
    var h = Handle();
    var c = copy(h);
    return 0;
}
"#;

#[test]
fn cannot_copy_offers_a_copyable_skeleton() {
    let (uri, text, program) = load("not_copyable", NOT_COPYABLE, "main.pep");
    let diagnostics = fixable_diagnostics(&text, Some(&program), Some(&sema_model_of(&program)));
    let [error] = diagnostics.as_slice() else { panic!("{diagnostics:?}") };
    // The runtime also declares a 'Handle', so this one is mangled ('Handle@main') until the message is shown.
    assert_eq!(demangle(&error.message), "cannot copy 'Handle', which is not trivially copyable");
    let actions = quick_fixes(&uri, &text, &diagnostics, Range::new(Position::new(9, 13), Position::new(9, 13)));
    let [CodeActionOrCommand::CodeAction(action)] = actions.as_slice() else { panic!("{actions:?}") };
    assert_eq!(action.title, "Implement Copyable<Handle>");
    let edits = &action.edit.as_ref().unwrap().changes.as_ref().unwrap()[&uri];
    let [edit] = edits.as_slice() else { panic!("{edits:?}") };
    // Inserted after the struct's closing brace.
    assert_eq!(edit.range, Range::new(Position::new(5, 1), Position::new(5, 1)));
    assert!(edit.new_text.starts_with("

extend Handle with Copyable<Handle> {
    copy(): Handle {"), "{}", edit.new_text);
}

const FRESH: &str = r#"make(name: String): Array<String> {
    var list = Array<String>();
    list.append(name + "!");
    return list;
}

same(list: Array<String>): Array<String> {
    return list;
}

main(): int {
    var a = make("x");
    var b = same(a);
    return 0;
}
"#;

#[test]
fn hover_says_when_a_function_returns_a_fresh_value() {
    let (uri, text, program) = load("fresh", FRESH, "main.pep");
    let hover_text = |needle: &str| {
        let offset = text.find(needle).unwrap();
        match PepperLsp::hover_at(&uri, &text, Some(&program), sema_model_of(&program).ok().as_ref(), offset).map(|h| h.contents) {
            Some(HoverContents::Markup(m)) => m.value,
            other => panic!("{other:?}"),
        }
    };
    assert!(hover_text("make(\"x\")").contains("Returns a fresh value"), "{}", hover_text("make(\"x\")"));
    assert!(!hover_text("same(a)").contains("Returns a fresh value"), "{}", hover_text("same(a)"));
}

const CONVERTED: &str = r#"struct Name {
    var text: String;
    [Implicit]
    construct(String text = "") { this.text = text; }
}

greet(n: Name): String { return n.text; }

main(): int {
    var who = "ada";
    greet(who);
    greet("bob");
    var typed: Name = who;
    var plain = "stays a String";
    return 0;
}
"#;

#[test]
fn hover_shows_implicit_conversions() {
    let (uri, text, program) = load("conversions", CONVERTED, "main.pep");
    let note = "Converted to `Name` by its `[Implicit]` constructor from `String`.";
    let variable = hover(&uri, &text, &program, at(&text, "greet(who)", 0, 7));
    assert!(variable.contains(note), "{}", variable);
    let literal = hover(&uri, &text, &program, at(&text, "\"bob\"", 0, 2));
    assert!(literal.contains(note), "{}", literal);
    let initializer = hover(&uri, &text, &program, at(&text, "= who", 0, 3));
    assert!(initializer.contains(note), "{}", initializer);
    let plain = hover(&uri, &text, &program, at(&text, "\"stays", 0, 2));
    assert!(!plain.contains("Converted"), "{}", plain);
}

#[test]
fn inlay_hints_wrap_converted_values() {
    let (_, text, program) = load("conversion_hints", CONVERTED, "main.pep");
    let sema = sema_model_of(&program).expect("sema");
    let hints: Vec<(Position, String)> = conversion_hints(&text, &sema)
        .into_iter()
        .map(|h| match h.label {
            InlayHintLabel::String(label) => (h.position, label),
            other => panic!("{other:?}"),
        })
        .collect();
    let position = |needle: &str, delta: usize| byte_to_lsp_pos(&text, at(&text, needle, 0, delta));
    assert_eq!(hints, vec![
        (position("who);", 0), "Name(".to_string()),
        (position("who);", 3), ")".to_string()),
        (position("\"bob\"", 0), "Name(".to_string()),
        (position("\"bob\"", 5), ")".to_string()),
        (position("who;", 0), "Name(".to_string()),
        (position("who;", 3), ")".to_string()),
    ]);
}

const OVERLOADED: &str = r#"## Scales a whole number.
scale(x: int): int { return x * 2; }
## Scales a fraction.
scale(x: double): double { return x * 3.0; }
scale(s: String): int { return 0; }

main(): int {
    var a = scale(2.5);
    var f: (int) => int = scale;
    return scale(4) + f(1);
}
"#;

#[test]
fn hover_on_an_overloaded_call_shows_the_chosen_member() {
    let (uri, text, program) = load("overloads", OVERLOADED, "main.pep");
    let fraction = hover(&uri, &text, &program, at(&text, "scale(2.5)", 0, 1));
    assert!(fraction.starts_with("`scale` — `scale(x: double): double` (+2 overloads)"), "{}", fraction);
    assert!(fraction.contains("Scales a fraction."), "{}", fraction);
    let whole = hover(&uri, &text, &program, at(&text, "scale(4)", 0, 0));
    assert!(whole.contains("scale(x: int): int") && whole.contains("Scales a whole number."), "{}", whole);
    let value = hover(&uri, &text, &program, at(&text, "int = scale", 0, 7));
    assert!(value.contains("scale(x: int): int"), "{}", value);
}

#[test]
fn definition_of_an_overloaded_call_is_the_chosen_member() {
    let (uri, text, program) = load("overload_definition", OVERLOADED, "main.pep");
    let (_, rest) = definition(&uri, &text, &program, at(&text, "scale(2.5)", 0, 2));
    assert!(rest.starts_with("scale(x: double)"), "{}", rest);
    let (_, rest) = definition(&uri, &text, &program, at(&text, "scale(4)", 0, 2));
    assert!(rest.starts_with("scale(x: int)"), "{}", rest);
}

const COLORS: &str = r#"## A traffic light color.
enum Color {
    ## Stop.
    Red,
    Amber,
    Green,
}

score(c: Color): int {
    match (c) {
        Red => { return 1; }
    }
    return 0;
}

test(): int { return score(Color.Amber); }
"#;

#[test]
fn hover_on_an_enum_case_shows_its_value_and_docs() {
    let complete = COLORS.replace("Red => { return 1; }", "Red => { return 1; }\n        else => { return 2; }");
    let (uri, text, program) = load("enum_hover", &complete, "main.pep");
    let value = hover(&uri, &text, &program, at(&text, "Color.Amber", 0, 7));
    assert!(value.contains("Color.Amber = 1"), "{}", value);
    // While the program does not build, the case without its value.
    let (uri, text, program) = load("enum_hover_broken", COLORS, "main.pep");
    let value = hover(&uri, &text, &program, at(&text, "Color.Amber", 0, 7));
    assert!(value.contains("Color.Amber"), "{}", value);
    let enum_name = hover(&uri, &text, &program, at(&text, "Color.Amber", 0, 1));
    assert!(enum_name.contains("A traffic light color."), "{}", enum_name);
}

#[test]
fn completion_after_an_enum_name_lists_its_cases() {
    let text = COLORS.replace("Color.Amber", "Color.");
    let uri = Url::parse("file:///t.pep").unwrap();
    let offset = at(&text, "Color.)", 0, 6);
    assert!(parse_source(uri.as_str(), &text).is_err());
    let ast = parse_after_dot(&uri, &text, offset).expect("parses with a placeholder");
    let items = enum_cases_before(&ast, &text, offset).expect("cases");
    let labels: Vec<&str> = items.iter().map(|i| i.label.as_str()).collect();
    assert_eq!(labels, ["Red", "Amber", "Green", "from_value"]);
    assert_eq!(items[0].kind, Some(CompletionItemKind::ENUM_MEMBER));
}

/// A name right after a non-ASCII character (`─` in a comment banner) is
/// found whole; looking for it never slices inside that character.
#[test]
fn a_name_after_a_non_ascii_character_does_not_panic() {
    let text = "#─String.format\n#─Color.";
    let offset = text.find("String").unwrap();
    assert_eq!(word_at(text, offset + 1), Some(Span { start: offset, end: offset + "String".len() }));
    assert_eq!(string_format_at(text, offset + 1), None);
    let module = parse_source("t.pep", text).unwrap();
    assert!(enum_cases_before(&module, text, text.len()).is_none());
}

#[test]
fn a_match_missing_cases_offers_to_add_them() {
    let (uri, text, program) = load("enum_missing_arms", COLORS, "main.pep");
    let error = sema_model_of(&program).expect_err("missing cases");
    let at_match = Range::new(Position::new(9, 6), Position::new(9, 6));
    let Some(CodeActionOrCommand::CodeAction(action)) = missing_arms_fix(&uri, &text, &program, &error, at_match) else {
        panic!("no fix for {:?}", error.message)
    };
    assert_eq!(action.title, "Add the missing cases of 'Color'");
    let edits = &action.edit.as_ref().unwrap().changes.as_ref().unwrap()[&uri];
    assert_eq!(edits, &vec![TextEdit {
        range: Range::new(Position::new(11, 0), Position::new(11, 0)),
        new_text: "        Amber => {}\n        Green => {}\n".to_string(),
    }]);
    // Nothing away from the error.
    assert!(missing_arms_fix(&uri, &text, &program, &error, Range::new(Position::new(0, 0), Position::new(0, 1))).is_none());
}

const SHAPES: &str = r#"## A shape to draw.
enum Shape {
    ## A circle.
    Circle(radius: int),
    Rect(width: int, height: int),
    Empty,
}

area(s: Shape): int {
    match (s) {
        Empty => { return 0; }
    }
    return 0;
}

test(): int { return area(Shape.Rect(2, 3)); }
"#;

#[test]
fn hover_and_completion_show_the_values_a_case_carries() {
    let complete = SHAPES.replace("Empty => { return 0; }", "Empty => { return 0; }\n        else => { return 1; }");
    let (uri, text, program) = load("payload_hover", &complete, "main.pep");
    let shown = hover(&uri, &text, &program, at(&text, "Shape.Rect", 0, 7));
    assert!(shown.contains("Shape.Rect(width: int, height: int)"), "{}", shown);
    // While the program does not build, from the document.
    let (uri, text, program) = load("payload_hover_broken", SHAPES, "main.pep");
    let shown = hover(&uri, &text, &program, at(&text, "Shape.Rect", 0, 7));
    assert!(shown.contains("Shape.Rect(width: int, height: int)"), "{}", shown);

    let text = SHAPES.replace("Shape.Rect(2, 3)", "Shape.");
    let offset = at(&text, "Shape.)", 0, 6);
    let ast = parse_after_dot(&uri, &text, offset).expect("parses with a placeholder");
    let items = enum_cases_before(&ast, &text, offset).expect("cases");
    let labels: Vec<&str> = items.iter().map(|i| i.label.as_str()).collect();
    assert_eq!(labels, ["Circle", "Rect", "Empty"]);
    assert_eq!(items[0].detail.as_deref(), Some("Shape.Circle(radius: int)"));
}

#[test]
fn a_match_missing_cases_with_values_binds_them() {
    let (uri, text, program) = load("payload_missing_arms", SHAPES, "main.pep");
    let error = sema_model_of(&program).expect_err("missing cases");
    let at_match = Range::new(Position::new(9, 6), Position::new(9, 6));
    let Some(CodeActionOrCommand::CodeAction(action)) = missing_arms_fix(&uri, &text, &program, &error, at_match) else {
        panic!("no fix for {:?}", error.message)
    };
    let edits = &action.edit.as_ref().unwrap().changes.as_ref().unwrap()[&uri];
    assert_eq!(edits[0].new_text, "        Circle(radius) => {}\n        Rect(width, height) => {}\n");
}

const OVERLOADED_METHODS: &str = r#"struct Meter {
    var n: int;
    ## Adds a whole number.
    add(x: int): int { return n + x; }
    ## Adds a fraction.
    add(x: double): double { return 0.5; }
}

main(): int {
    var m = Meter();
    var a = m.add(2.5);
    return m.add(1);
}
"#;

#[test]
fn hover_and_definition_of_an_overloaded_method_call() {
    let (uri, text, program) = load("method_overloads", OVERLOADED_METHODS, "main.pep");
    let fraction = hover(&uri, &text, &program, at(&text, "add(2.5)", 0, 1));
    assert!(fraction.starts_with("`add` — `add(x: double): double` (+1 overload)"), "{}", fraction);
    assert!(fraction.contains("Adds a fraction."), "{}", fraction);
    let (_, rest) = definition(&uri, &text, &program, at(&text, "add(1)", 0, 1));
    assert!(rest.starts_with("add(x: int)"), "{}", rest);
}


/// Source nested as deeply as the parser allows (`MAX_NESTING`), in each
/// shape that nests: a `+` chain, parentheses, calls, blocks, `else if`,
/// unary operators, and method chains.
fn deepest_programs() -> Vec<(&'static str, String)> {
    use pepper_parser::parser::MAX_NESTING;
    let n = MAX_NESTING - 4;
    let wrap = |body: String| format!("f(x: int): int {{ return x; }}\nexport main(): int {{\n    var x = 1;\n{body}\n    return x;\n}}\n");
    vec![
        ("chain", wrap(format!("    x = 1{};", " + x".repeat(n)))),
        ("parentheses", wrap(format!("    x = {}x{};", "(".repeat(n), ")".repeat(n)))),
        ("calls", wrap(format!("    x = {}x{};", "f(".repeat(n / 2), ")".repeat(n / 2)))),
        ("blocks", wrap(format!("{}x = 2;{}", "if (x == 1) {\n".repeat(n), "}\n".repeat(n)))),
        ("else if", wrap(format!("    if (x == 0) {{ x = 1; }}{}", " else if (x == 2) { x = 3; }".repeat(n / 2)))),
        ("unary", wrap(format!("    x = {}x;", "- ".repeat(n)))),
        ("strings", wrap(format!("    var s = \"a\"{};", " + \"a\"".repeat(n)))),
    ]
}

/// Every pass the server runs fits in `STACK_SIZE` on the deepest source the
/// parser accepts; a stack overflow cannot be caught, and ends the server.
#[test]
fn deepest_source_fits_the_server_stack() {
    for (shape, main) in deepest_programs() {
        std::thread::Builder::new()
            .stack_size(STACK_SIZE)
            .spawn(move || {
                let (_, _, program) = load(&format!("deepest_{}", shape.replace(' ', "_")), &main, "main.pep");
                assert!(sema_model_of(&program).is_ok(), "{shape}");
            })
            .unwrap()
            .join()
            .unwrap_or_else(|_| panic!("{shape}"));
    }
}

/// A request whose analysis panics answers with nothing; the server lives on.
#[test]
fn guarded_turns_a_panic_into_none() {
    assert_eq!(guarded(|| 1), Some(1));
    assert_eq!(guarded(|| -> i32 { panic!("a bug in one request") }), None);
}

/// A server holding `text` as the document `uri`, analyzed as the
/// background analysis would.
fn analyzed_server(uri: &Url, text: &str) -> LspService<PepperLsp> {
    let (service, _) = LspService::new(PepperLsp::new);
    let documents = &service.inner().documents;
    let analysis = documents.set(uri, text.to_string());
    analyze(documents, &analysis);
    service
}

/// The text at `location`'s start, in `text`.
fn text_at<'a>(text: &'a str, location: &Location) -> &'a str {
    &text[line_col_to_byte(text, location.range.start.line, location.range.start.character)..]
}

/// After an edit, a definition that needs sema (the chosen overload) is
/// answered at once from the last analysis that passed, its place moved with
/// the edit; the request runs no sema of its own.
#[test]
fn definition_after_an_edit_reads_the_last_passed_analysis() {
    let (uri, text, _) = load("stale_overload", OVERLOADED, "main.pep");
    let service = analyzed_server(&uri, &text);
    let server = service.inner();
    let edited = format!("# A note.\n{}", text);
    let latest = server.documents.set(&uri, edited.clone());

    let definition = server.definition(&uri, at(&edited, "scale(2.5)", 0, 2)).expect("a definition");
    assert!(text_at(&edited, &definition[0]).starts_with("scale(x: double)"), "{:?}", definition);
    let definition = server.definition(&uri, at(&edited, "scale(4)", 0, 2)).expect("a definition");
    assert!(text_at(&edited, &definition[0]).starts_with("scale(x: int)"), "{:?}", definition);
    let hover = server.hover(&uri, at(&edited, "scale(2.5)", 0, 1)).expect("a hover");
    let HoverContents::Markup(hover) = hover.contents else { panic!() };
    assert!(hover.value.contains("Scales a fraction"), "{}", hover.value);
    assert!(hover.value.contains("Checking your latest edit"), "an older analysis's hover says so: {}", hover.value);
    assert!(latest.sema_if_done().is_none(), "requests run no sema");
    // Once the edit checks, the note goes.
    analyze(&server.documents, &latest);
    let hover = server.hover(&uri, at(&edited, "scale(2.5)", 0, 1)).expect("a hover");
    let HoverContents::Markup(hover) = hover.contents else { panic!() };
    assert!(!hover.value.contains("latest edit"), "{}", hover.value);
    // An edit that does not parse is checked, and the note says it fails.
    let broken = format!("{}\nmain(: int {{", edited);
    let latest = server.documents.set(&uri, broken.clone());
    analyze(&server.documents, &latest);
    let hover = server.hover(&uri, at(&broken, "scale(2.5)", 0, 1)).expect("a hover");
    let HoverContents::Markup(hover) = hover.contents else { panic!() };
    assert!(hover.value.contains("does not check yet"), "{}", hover.value);
}

/// A name inside what changed since the last passed analysis is answered
/// from the current text, without sema.
#[test]
fn definition_inside_an_edit_reads_the_current_text() {
    let main = "twice(x: int): int { return x * 2; }\nmain(): int { return twice(1); }\n";
    let (uri, text, _) = load("stale_edit", main, "main.pep");
    let service = analyzed_server(&uri, &text);
    let server = service.inner();
    let edited = text.replace("return twice(1);", "return thrice(1);") + "thrice(x: int): int { return x * 3; }\n";
    server.documents.set(&uri, edited.clone());

    let definition = server.definition(&uri, at(&edited, "thrice(1)", 0, 2)).expect("a definition");
    assert!(text_at(&edited, &definition[0]).starts_with("thrice(x: int)"), "{:?}", definition);
}

/// Every reader of one text shares one analysis; an edit makes a new one.
#[test]
fn one_text_has_one_analysis() {
    let (uri, text, _) = load("shared_analysis", OVERLOADED, "main.pep");
    let service = analyzed_server(&uri, &text);
    let documents = &service.inner().documents;
    let first = documents.latest(&uri).unwrap();
    assert!(first.sema_model().is_some(), "the analysis passed");
    assert!(Arc::ptr_eq(&first, &documents.view(&uri).unwrap().ready.unwrap().0));
    let edited = documents.set(&uri, text.replace("2.5", "3.5"));
    assert!(!Arc::ptr_eq(&first, &edited));
    assert!(documents.is_latest(&edited) && !documents.is_latest(&first));
}

#[test]
fn edit_map_carries_offsets_around_the_edit() {
    let old = "var alpha = 1;\nvar beta = 2;\n";
    let new = "var alpha = 1;\nvar gamma = 3;\nvar beta = 2;\n";
    let edits = analysis::EditMap::between(old, new);
    // Before the edit, and after it.
    assert_eq!(edits.to_old(new, at(new, "alpha", 0, 2)), Some(at(old, "alpha", 0, 2)));
    assert_eq!(edits.to_old(new, at(new, "beta", 0, 1)), Some(at(old, "beta", 0, 1)));
    // Inside it.
    assert_eq!(edits.to_old(new, at(new, "gamma", 0, 1)), None);
    let beta = span_to_range(old, Span { start: at(old, "beta", 0, 0), end: at(old, "beta", 0, 4) });
    assert_eq!(edits.range_to_new(old, new, beta), Some(span_to_range(new, Span { start: at(new, "beta", 0, 0), end: at(new, "beta", 0, 4) })));
    // An empty range at the start of the line a new line went above moves
    // down with it.
    let start = Range::new(Position::new(1, 0), Position::new(1, 0));
    assert_eq!(edits.range_to_new(old, new, start), Some(Range::new(Position::new(2, 0), Position::new(2, 0))));

    // A name on an edited line does not map: editing `p.x` to `q.x`
    // changes what `x` is.
    let (old, new) = ("f(ab);", "f(abc);");
    assert_eq!(analysis::EditMap::between(old, new).to_old(new, 3), None);
    let (old, new) = ("var a = p.x;\nb;\n", "var a = q.x;\nb;\n");
    let edits = analysis::EditMap::between(old, new);
    assert_eq!(edits.to_old(new, at(new, "x;", 0, 0)), None);
    assert_eq!(edits.to_old(new, at(new, "b;", 0, 0)), Some(at(old, "b;", 0, 0)));
    // So do answers that came from it, such as a hint around `x`.
    let x = span_to_range(old, Span { start: at(old, "x;", 0, 0), end: at(old, "x;", 0, 1) });
    assert_eq!(edits.line_range_to_new(old, new, x), None);
    let b = span_to_range(old, Span { start: at(old, "b;", 0, 0), end: at(old, "b;", 0, 1) });
    assert_eq!(edits.line_range_to_new(old, new, b), Some(b));

    // An edit inside a multi-byte character splits at a character boundary.
    let (old, new) = ("a = \"é\";\nb", "a = \"è\";\nb");
    let edits = analysis::EditMap::between(old, new);
    assert_eq!(edits.to_old(new, new.len() - 1), Some(old.len() - 1));
}

const CONSTRAINED: &str = r#"trait Shape {
    area(): int;
}

struct Circle {
    area(): int { return 3; }
}

struct Gallery<T: Shape> {
    var items = Array<T>();
}

total<T: Shape>(items: Array<T>): int { return 0; }

wrap<T>(item: T): Gallery<T> { return Gallery<T>(); }

main(): int {
    return total(Array<Circle>());
}
"#;

#[test]
fn hover_shows_generic_constraints() {
    let (uri, text, program) = load("constraints_hover", CONSTRAINED, "main.pep");
    let total = hover(&uri, &text, &program, at(&text, "total(Array", 0, 0));
    assert!(total.contains("total<T: Shape>(items: Array<T>): int"), "{}", total);
}

#[test]
fn an_unconstrained_parameter_offers_to_constrain_it() {
    let (uri, text, program) = load("constraints_fix", CONSTRAINED, "main.pep");
    let diagnostics = fixable_diagnostics(&text, Some(&program), Some(&sema_model_of(&program)));
    let [error] = diagnostics.as_slice() else { panic!("{diagnostics:?}") };
    assert_eq!(error.message, "'T' does not conform to trait 'Shape', required by 'T' in 'Gallery'");
    let actions = quick_fixes(&uri, &text, &diagnostics, Range::new(Position::new(14, 26), Position::new(14, 26)));
    let [CodeActionOrCommand::CodeAction(action)] = actions.as_slice() else { panic!("{actions:?}") };
    assert_eq!(action.title, "Constrain 'T' to 'Shape'");
    let edits = &action.edit.as_ref().unwrap().changes.as_ref().unwrap()[&uri];
    let [edit] = edits.as_slice() else { panic!("{edits:?}") };
    // Inserted after `wrap<T`.
    assert_eq!(edit.range, Range::new(Position::new(14, 6), Position::new(14, 6)));
    assert_eq!(edit.new_text, ": Shape");
}

#[test]
fn a_type_that_does_not_conform_offers_the_extension() {
    let main = CONSTRAINED.replace("wrap<T>", "wrap<T: Shape>");
    let (uri, text, program) = load("constraints_extend", &main, "main.pep");
    let diagnostics = fixable_diagnostics(&text, Some(&program), Some(&sema_model_of(&program)));
    let [error] = diagnostics.as_slice() else { panic!("{diagnostics:?}") };
    assert_eq!(error.message, "'Circle' does not conform to trait 'Shape', required by 'T' in 'total'");
    let actions = quick_fixes(&uri, &text, &diagnostics, Range::new(Position::new(17, 17), Position::new(17, 17)));
    let [CodeActionOrCommand::CodeAction(action)] = actions.as_slice() else { panic!("{actions:?}") };
    assert_eq!(action.title, "Declare 'extend Circle with Shape'");
    let edits = &action.edit.as_ref().unwrap().changes.as_ref().unwrap()[&uri];
    let [edit] = edits.as_slice() else { panic!("{edits:?}") };
    assert_eq!(edit.range, Range::new(Position::new(6, 1), Position::new(6, 1)));
    assert_eq!(edit.new_text, "\n\nextend Circle with Shape {\n}");
}

/// An imported file that changes on disk reaches the document's answers
/// once its fresh analysis passes, though the document's own text is
/// unchanged; until then they come from the old one.
#[test]
fn a_changed_import_refreshes_the_analysis() {
    let main = "import \"util\";\nmain(): int { return twice(2); }\n";
    let (uri, text, _) = load("changed_import", main, "main.pep");
    let service = analyzed_server(&uri, &text);
    let server = service.inner();
    let call = at(&text, "twice(2)", 0, 1);
    assert_eq!(server.definition(&uri, call).expect("a definition")[0].range.start.line, 0);

    let other = uri.to_file_path().unwrap().with_file_name("other.pep");
    assert!(server.documents.forget(std::slice::from_ref(&other), false).is_empty(), "an unrelated file changes nothing");
    let util = uri.to_file_path().unwrap().with_file_name("util.pep");
    let source = std::fs::read_to_string(&util).unwrap();
    std::fs::write(&util, format!("# Moved down a line.\n{}", source)).unwrap();
    let old = server.documents.latest(&uri).unwrap();
    assert!(!old.is_current());
    // Until the fresh analysis passes, from the current text: the new place.
    assert_eq!(server.definition(&uri, call).expect("a definition")[0].range.start.line, 1);
    let fresh = server.documents.latest(&uri).unwrap();
    assert!(fresh.generation > old.generation, "a request notices the change");
    analyze(&server.documents, &fresh);
    assert_eq!(server.definition(&uri, call).expect("a definition")[0].range.start.line, 1);

    // The editor's word about it, spelled as the editor spells the path.
    let spelled = Url::from_file_path(&util).unwrap().to_string();
    let spelled = match spelled.strip_prefix("file:///").and_then(|rest| rest.split_once(':')) {
        Some((drive, rest)) if drive.len() == 1 => format!("file:///{}%3A{}", drive.to_lowercase(), rest),
        _ => spelled,
    };
    let changed = Url::parse(&spelled).unwrap().to_file_path().unwrap();
    assert_eq!(server.documents.forget(&[changed], false).len(), 1);
    // A new file may change what an import resolves to: the passed
    // analysis no longer answers.
    analyze(&server.documents, &server.documents.latest(&uri).unwrap());
    assert!(server.documents.view(&uri).unwrap().ready.is_some());
    assert_eq!(server.documents.forget(&[other], true).len(), 1);
    assert!(server.documents.view(&uri).unwrap().ready.is_none());
}

/// An import whose file did not load (a parse error) is watched too:
/// fixing that file makes the analysis stale.
#[test]
fn fixing_an_import_that_did_not_load_refreshes_the_analysis() {
    let main = "import \"broken\";\nmain(): int { return 0; }\n";
    let (uri, text, _) = load("failed_import", main, "main.pep");
    let broken = uri.to_file_path().unwrap().with_file_name("broken.pep");
    std::fs::write(&broken, "export f(): int { return 1 + ; }\n").unwrap();
    backdate(&broken);
    let service = analyzed_server(&uri, &text);
    let analysis = service.inner().documents.latest(&uri).unwrap();
    analysis.program().expect("the program loads without the broken file");
    assert!(analysis.is_current());
    std::fs::write(&broken, "export f(): int { return 1; }\n# Fixed.\n").unwrap();
    assert!(!analysis.is_current(), "fixing the file that did not load makes the analysis stale");
    assert_eq!(service.inner().documents.forget(&[broken], false).len(), 1);
}

/// Renewing an analysis for a changed file never brings back text an edit
/// replaced, nor a document that closed.
#[test]
fn a_renewed_analysis_yields_to_edits_and_closes() {
    let main = "import \"util\";\nmain(): int { return twice(2); }\n";
    let (uri, text, _) = load("renew", main, "main.pep");
    let service = analyzed_server(&uri, &text);
    let documents = &service.inner().documents;
    let util = uri.to_file_path().unwrap().with_file_name("util.pep");
    let edited = text.replace("twice(2)", "twice(3)");
    documents.set(&uri, edited.clone());
    // The edit's analysis has not loaded its program yet: it counts as
    // affected, and its renewal keeps the edited text.
    let renewed = documents.forget(std::slice::from_ref(&util), false);
    assert_eq!(renewed.len(), 1);
    assert_eq!(documents.text(&uri).unwrap(), edited);
    documents.close(&uri);
    assert!(documents.forget(&[util], true).is_empty());
    assert!(documents.refresh(&uri).is_none() && documents.text(&uri).is_none(), "a closed document stays closed");
}

/// An analysis that passes after a renewal for changed files does not
/// answer: it may name what an import resolved to before.
#[test]
fn an_analysis_older_than_a_renewal_does_not_answer() {
    let (uri, text, _) = load("late_pass", OVERLOADED, "main.pep");
    let (service, _) = LspService::new(PepperLsp::new);
    let documents = &service.inner().documents;
    let old = documents.set(&uri, text);
    let created = uri.to_file_path().unwrap().with_file_name("new.pep");
    assert_eq!(documents.forget(&[created], true).len(), 1);
    analyze(documents, &old);
    assert!(documents.view(&uri).unwrap().ready.is_none());
}

const NESTED: &str = r#"import geometry as g;
struct Inner {
    var z: int;
    twice(): int { return z * 2; }
}
struct Outer { var y: Inner; }
struct Top {
    var o: Outer;
    f(): int { return this.o.y.z; }
}
main(): int {
    var x = Outer();
    var w: Outer = Outer();
    var p = g.make(1, 2);
    return x.y.z + w.y.twice() + p.y;
}
"#;

/// Go to Definition on each member of a chain (`x.y.z`), whatever the owner:
/// an inferred or declared local, `this`, a method call, the left operand of
/// a binary expression, or a struct from an imported module.
#[test]
fn definition_of_a_nested_member() {
    let (uri, text, program) = load("nested_member", NESTED, "main.pep");
    let starts = |offset: usize| definition(&uri, &text, &program, offset);
    // Each member of `this.o.y.z`.
    assert!(starts(at(&text, "o.y.z", 0, 0)).1.starts_with("o: Outer"));
    assert!(starts(at(&text, "y.z;", 0, 0)).1.starts_with("y: Inner"));
    assert!(starts(at(&text, "z;", 0, 0)).1.starts_with("z: int"));
    // `x.y.z` on an inferred local, the left operand of `+`.
    assert!(starts(at(&text, "x.y.z", 0, 0)).1.starts_with("x = Outer"));
    assert!(starts(at(&text, "y.z +", 0, 0)).1.starts_with("y: Inner"));
    assert!(starts(at(&text, "z +", 0, 0)).1.starts_with("z: int"));
    // A method reached through a member.
    let (_, rest) = starts(at(&text, "twice()", 1, 1));
    assert!(rest.starts_with("twice(): int"), "{}", rest);
    // A field of a struct another file declares.
    let (file, rest) = starts(at(&text, "p.y", 0, 2));
    assert_eq!(file, "geometry/module.pep");
    assert!(rest.starts_with("y: int"), "{}", rest);
}

const SYNTHESIZED: &str = r#"struct Money {
    var cents: int;
    +(other: Money): Money { var m = Money(); m.cents = cents + other.cents; return m; }
}
main(): int {
    var xs = [1, 2];
    var i = 0;
    var total = xs[i];
    for (var v in xs) { total = total + v; }
    var a = Money();
    var b = a + a;
    var c = b.cents > 0 ? 1 : 2;
    var d = (a + b).cents;
    var f = (): int => { return b.cents; };
    return total + b.cents + c + d + f();
}
"#;

/// A name sema wrapped in a call of its own (an index, a loop, an
/// operator, a literal) still goes to its declaration, not the call's.
#[test]
fn definition_inside_a_synthesized_call_is_the_name() {
    let (uri, text, program) = load("synthesized", SYNTHESIZED, "main.pep");
    let starts = |needle: &str, nth: usize| definition(&uri, &text, &program, at(&text, needle, nth, 0)).1;
    assert!(starts("xs[i]", 0).starts_with("xs = [1"));
    assert!(starts("i];", 0).starts_with("i = 0"));
    assert!(starts("xs) {", 0).starts_with("xs = [1"));
    assert!(starts("a + a", 0).starts_with("a = Money"));
    assert!(starts("a;\n", 0).starts_with("a = Money"));
    assert!(starts("cents;", 0).starts_with("cents: int"));
    // The condition of a ternary starts before its operator.
    assert!(starts("b.cents > 0", 0).starts_with("b = a"));
    // The left operand of a call's owner.
    assert!(starts("a + b)", 0).starts_with("a = Money"));
    // A local a closure captures is not a member of the closure: no jump
    // to the use itself.
    let captured = at(&text, "b.cents; }", 0, 0);
    let found = PepperLsp::definition_at(&uri, &text, Some(&program), sema_model_of(&program).ok().as_ref(), captured);
    let used = byte_to_lsp_pos(&text, captured);
    assert!(found.as_ref().is_none_or(|l| l[0].range.start != used), "{:?}", found);
}

const INFERRED: &str = r#"struct Core {
    ## Whether the task finished.
    var finished: bool;
}
struct Worker {
    ## The task's shared state.
    var core: Core;
}
worker_of(): Worker { return Worker(); }
main(): int {
    var worker = worker_of();
    var done = worker.core.finished;
    return 0;
}
"#;

/// A local whose type sema inferred hovers with that type, and so do the
/// fields reached through it (`worker.core.finished`), with their docs.
#[test]
fn hover_on_an_inferred_local_and_its_fields() {
    let (uri, text, program) = load("inferred_hover", INFERRED, "main.pep");
    let worker = hover(&uri, &text, &program, at(&text, "worker.core", 0, 0));
    assert!(worker.contains("`worker` — `Worker`"), "{}", worker);
    let core = hover(&uri, &text, &program, at(&text, "core.finished", 0, 0));
    assert!(core.contains("`Core`") && core.contains("shared state"), "{}", core);
    let finished = hover(&uri, &text, &program, at(&text, "finished;", 0, 0));
    assert!(finished.contains("`bool`") && finished.contains("task finished"), "{}", finished);
    let done = hover(&uri, &text, &program, at(&text, "done", 0, 0));
    assert!(done.contains("`bool`"), "{}", done);
}


const ASSIGNED: &str = r#"struct Core { var n: int; }
struct Task {
    ## What the scheduler knows about the task.
    var core: Core;
    construct(start: Core) {
        this.core = start;
    }
    swap(other: Core): int {
        this.core = other;
        return other.n;
    }
}
extend Task {
    bump(by: int): int {
        var total = by + this.core.n;
        return total;
    }
}
"#;

/// Parameters are in scope (in constructors, methods and extensions), and
/// the left side of an assignment hovers, though the parser starts an
/// assignment's span at its `=`.
#[test]
fn hover_on_parameters_and_assigned_fields() {
    let (uri, text, program) = load("assigned_hover", ASSIGNED, "main.pep");
    let field = hover(&uri, &text, &program, at(&text, "core = start", 0, 1));
    assert!(field.contains("`.core` — `Core`") && field.contains("scheduler knows"), "{}", field);
    let start = hover(&uri, &text, &program, at(&text, "start;", 0, 1));
    assert!(start.contains("`start` — `Core`"), "{}", start);
    let other = hover(&uri, &text, &program, at(&text, "other.n", 0, 1));
    assert!(other.contains("`other` — `Core`"), "{}", other);
    let by = hover(&uri, &text, &program, at(&text, "by + this", 0, 0));
    let core = hover(&uri, &text, &program, at(&text, "core.n;", 0, 1));
    assert!(core.contains("`.core` — `Core`") && core.contains("scheduler knows"), "in an extension: {}", core);
    assert!(by.contains("`by` — `int`"), "{}", by);
    assert!(definition(&uri, &text, &program, at(&text, "start;", 0, 1)).1.starts_with("start: Core"));
    assert!(definition(&uri, &text, &program, at(&text, "total;", 0, 1)).1.starts_with("total = by"));
}

const EXTENSIONS: &str = r#"struct Point {
    var x: int;
    ## Spells the point.
    to_string(): String { return "p"; }
}
extend Point {
    describe(): String { return to_string(); }
}
extend Array<int> {
    total(): int { return 0; }
}
"#;

/// In an extension, a bare call of the type's method is that method, not a
/// global of the same name; a concrete argument of the extended type is no
/// type parameter.
#[test]
fn extension_members_and_arguments() {
    let (uri, text, program) = load("extension_members", EXTENSIONS, "main.pep");
    let call = at(&text, "to_string();", 0, 1);
    let (file, rest) = definition(&uri, &text, &program, call);
    assert_eq!(file, file_label(&uri.to_file_path().unwrap().to_string_lossy()));
    assert!(rest.starts_with("to_string(): String"), "{}", rest);
    assert!(hover(&uri, &text, &program, call).contains("Spells the point"));
    let int = hover(&uri, &text, &program, at(&text, "int {", 0, 1));
    assert!(!int.contains("type parameter"), "{}", int);
}

const MATCHED: &str = r#"enum Found {
    Hit(hash: int),
    Miss,
}
look(f: Found): int {
    match (f) {
        Hit(hash) => { return hash; }
        Miss => { return 0; }
    }
    return 0;
}
const double = (hash: int): int => hash * 2;
"#;

/// A name a `match` arm binds is a local of the arm, not the runtime's
/// global of the same name.
#[test]
fn a_match_binding_is_local() {
    let (uri, text, program) = load("match_binding", MATCHED, "main.pep");
    let (file, rest) = definition(&uri, &text, &program, at(&text, "hash; }", 0, 1));
    assert_eq!(file, file_label(&uri.to_file_path().unwrap().to_string_lossy()));
    assert!(rest.starts_with("hash) =>"), "{}", rest);
    // A parameter of a closure at module scope.
    let (file, rest) = definition(&uri, &text, &program, at(&text, "hash * 2", 0, 1));
    assert_eq!(file, file_label(&uri.to_file_path().unwrap().to_string_lossy()));
    assert!(rest.starts_with("hash: int)"), "{}", rest);
}

const TRAIT_CALL: &str = r#"trait Driver {
    ## Waits for events, at most `timeout` milliseconds.
    poll(timeout: int): bool;
}
struct Quiet { poll(timeout: int): bool { return false; } }
extend Quiet with Driver;
struct Worker {
    var driver: Driver;
    tick(): bool { return this.driver.poll(5); }
}
"#;

/// A method called on a trait-typed value hovers with the trait's
/// signature and doc comment.
#[test]
fn hover_on_a_trait_method_call() {
    let (uri, text, program) = load("trait_call", TRAIT_CALL, "main.pep");
    let shown = hover(&uri, &text, &program, at(&text, "poll(5)", 0, 1));
    assert!(shown.contains("poll(timeout: int): bool") && shown.contains("Waits for events"), "{}", shown);
}

const PLATFORMS: &str = r#"[Target(OS(Windows))]
import "win_only";

[Target(OS(Linux))]
open_linux(): int { return 1; }

[Target(OS(Windows))]
open_windows(): int { return 2; }

struct File {
    var size: int;

    [Target(OS(Windows))]
    construct() {}

    [Target(OS(Windows))]
    close() {}

    read(): int {
        [Target(OS(Windows))] {
            return 1;
        }
        [Target(!OS(Windows))] {
            return 2;
        }
        for (var i in [1, 2]) {
            [Target(OS(Windows))] {
                return i;
            }
        }
        return 0;
    }
}
"#;

/// On Linux, the Windows-only import, function, method and block are
/// dimmed, each from its attribute; the Linux code and what has no target
/// stay as they are.
#[test]
fn code_for_other_platforms_is_dimmed() {
    let module = parse_source("main.pep", PLATFORMS).unwrap();
    let regions = pepper_sema::passes::platform::with_simulated_host("linux", "x86_64", || {
        platforms::inactive_regions(PLATFORMS, &module)
    });
    let dimmed: Vec<&str> = regions.iter().map(|s| PLATFORMS[s.start..s.end].lines().next().unwrap()).collect();
    // Not the constructor: it is compiled whatever its attributes.
    assert!(dimmed.len() == 5 && dimmed.iter().all(|l| l.starts_with("[Target(OS(Windows))]")), "{:?}", regions);
    let ends: Vec<&str> = regions.iter().map(|s| PLATFORMS[s.start..s.end].lines().last().unwrap().trim()).collect();
    assert_eq!(ends, ["import \"win_only\"", "open_windows(): int { return 2; }", "close() {}", "}", "}"]);
    let hints = pepper_sema::passes::platform::with_simulated_host("linux", "x86_64", || inactive_hints(PLATFORMS, &module));
    assert!(hints.iter().all(|h| h.tags == Some(vec![DiagnosticTag::UNNECESSARY]) && h.message.contains("Linux x86_64")));
}

#[test]
fn a_kept_syntax_tree_is_reused_only_for_the_same_text() {
    use pepper_sema::program::ParseCache;
    let parsed = analysis::Parsed(std::sync::Mutex::new(HashMap::new()));
    let path = std::path::Path::new("kept.pep");
    let tree = parse_source("kept.pep", "main(): int { return 0; }").unwrap();
    parsed.put(path, "main(): int { return 0; }", &tree);
    assert!(parsed.get(path, "main(): int { return 0; }").is_some());
    assert!(parsed.get(path, "main(): int { return 1; }").is_none());
    assert!(parsed.get(std::path::Path::new("other.pep"), "main(): int { return 0; }").is_none());
}

const LINUX_ONLY: &str = r#"struct Socket { var handle: int; }
[Target(OS(Linux))]
open_socket(): Socket { return Socket(); }
[Target(OS(Linux))]
handle_of(): int {
    var socket = open_socket();
    return socket.handle;
}
"#;

/// A file of Linux-only code, opened while building for Windows, is
/// analyzed as Linux, so its names have types; its code is still dimmed.
#[test]
fn a_file_for_another_os_is_analyzed_for_it() {
    let (uri, text, _) = load("linux_only", LINUX_ONLY, "main.pep");
    pepper_sema::passes::platform::with_simulated_host("windows", "x86_64", || {
        let (service, _) = LspService::new(PepperLsp::new);
        let documents = &service.inner().documents;
        let analysis = documents.set(&uri, text.clone());
        assert_eq!(analysis.os(), "linux");
        analyze(documents, &analysis);
        assert!(analysis.sema_model().is_some(), "{:?}", analysis.sema().map(|s| s.as_ref().err().map(|e| e.message.clone())));
        let shown = service.inner().hover(&uri, at(&text, "socket.handle", 0, 0)).expect("a hover");
        let HoverContents::Markup(shown) = shown.contents else { panic!() };
        assert!(shown.value.contains("`socket` — `Socket`"), "{}", shown.value);
        let module = parse_source("main.pep", &text).unwrap();
        assert_eq!(inactive_hints(&text, &module).len(), 2, "dimmed for the build target");
    });
}

/// A file with code for both the build target and another OS is analyzed
/// for the build target, whose code the editor shows undimmed.
#[test]
fn a_file_with_code_for_the_build_target_is_analyzed_for_it() {
    let both = format!("{}[Target(OS(Windows))]\nwindows_only(): int {{ return 1; }}\n", LINUX_ONLY);
    let (uri, text, _) = load("both_os", &both, "main.pep");
    pepper_sema::passes::platform::with_simulated_host("windows", "x86_64", || {
        let analysis = analysis::Analysis::new(uri.clone(), text.clone(), 0);
        assert_eq!(analysis.os(), "windows");
    });
}

/// A mostly portable file with one function for another OS stays on the
/// build target, so a call the build target rejects still shows its error.
#[test]
fn a_mostly_portable_file_stays_on_the_build_target() {
    let mixed = "[Target(OS(Linux))]
foo(): int { return 1; }
bar(): int { return foo(); }
baz(): int { return bar() + 1; }
qux(): int { return baz() + bar() + 2; }
";
    let (uri, text, _) = load("mostly_portable", mixed, "main.pep");
    pepper_sema::passes::platform::with_simulated_host("windows", "x86_64", || {
        assert_eq!(analysis::Analysis::new(uri.clone(), text.clone(), 0).os(), "windows");
    });
}

const MATCHED_SHAPES: &str = r#"enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
    Point,
}

enum List {
    Empty,
    Cons(head: int, tail: List),
}

area(s: Shape): int {
    return match (s) {
        Circle(r) => 3 * r * r,
        Rect(w, h) => w * h,
        Point => 0,
    };
}

sum(list: List): int {
    var total = 0;
    var rest = list;
    while (rest is Cons(head, tail)) {
        total += head;
        rest = tail;
    }
    return total;
}
"#;

/// A pattern's case goes to the case and hovers with the values it carries;
/// a name the pattern binds has the type of its value, where it is bound and
/// where it is used.
#[test]
fn match_patterns_and_their_bindings() {
    let (uri, text, program) = load("match_patterns", MATCHED_SHAPES, "main.pep");
    let circle = at(&text, "Circle(r)", 0, 0);
    let h = hover(&uri, &text, &program, circle);
    assert!(h.starts_with("`Circle` — `Shape.Circle(radius: int)`"), "{}", h);
    assert!(definition(&uri, &text, &program, circle).1.starts_with("Circle(radius"));
    // The binding where it is bound, and where it is used.
    for offset in [at(&text, "Circle(r)", 0, 7), at(&text, "r * r", 0, 0), at(&text, "* r,", 0, 2)] {
        let h = hover(&uri, &text, &program, offset);
        assert!(h.starts_with("`r` — `int`"), "{}", h);
        assert!(definition(&uri, &text, &program, offset).1.starts_with("r) =>"));
    }
    assert!(hover(&uri, &text, &program, at(&text, "w * h", 0, 0)).starts_with("`w` — `int`"));
    assert!(definition(&uri, &text, &program, at(&text, "Point =>", 0, 0)).1.starts_with("Point,"));
    // An `is` test's case and bindings, and their uses in its block.
    assert!(definition(&uri, &text, &program, at(&text, "Cons(head, tail)", 0, 0)).1.starts_with("Cons(head: int"));
    assert!(hover(&uri, &text, &program, at(&text, "tail))", 0, 0)).starts_with("`tail` — `List`"));
    assert!(hover(&uri, &text, &program, at(&text, "= tail;", 0, 2)).starts_with("`tail` — `List`"));
    assert!(definition(&uri, &text, &program, at(&text, "+= head", 0, 3)).1.starts_with("head, tail)"));
}

/// A pattern nested in a case's values goes to its case, and a name it binds
/// has the type of the nested case's value.
#[test]
fn nested_patterns_and_their_bindings() {
    let source = format!(
        "{}{}",
        MATCHED_SHAPES,
        "second(list: List): int {\n    return match (list) {\n        Cons(_, Cons(next, _)) => next,\n        else => 0,\n    };\n}\n"
    );
    let (uri, text, program) = load("nested_patterns", &source, "main.pep");
    let nested = at(&text, "Cons(next", 0, 0);
    assert!(definition(&uri, &text, &program, nested).1.starts_with("Cons(head: int"));
    let h = hover(&uri, &text, &program, at(&text, "next, _", 0, 0));
    assert!(h.starts_with("`next` — `int`"), "{}", h);
    assert!(hover(&uri, &text, &program, at(&text, "=> next", 0, 3)).starts_with("`next` — `int`"));
}

/// The values an enum case carries hover where they are declared, and their
/// types go to their declarations.
#[test]
fn enum_case_values_where_they_are_declared() {
    let (uri, text, program) = load("enum_case_values", MATCHED_SHAPES, "main.pep");
    let h = hover(&uri, &text, &program, at(&text, "radius", 0, 0));
    assert!(h.starts_with("`radius` — `int`"), "{}", h);
    assert!(definition(&uri, &text, &program, at(&text, "height", 0, 0)).1.starts_with("height: int"));
    assert!(definition(&uri, &text, &program, at(&text, "tail: List", 0, 6)).1.starts_with("List {"));
}

const UNINSTANTIATED: &str = r#"struct Box<T> {
    var value: T;
    construct(value: T) { this.value = value; }
    get(): T { return value; }
    static make(value: T): Box<T> { return Box<T>(value); }
}

struct Holder {
    var sizes: Array<int>;
    construct() { sizes = Array<int>(); }

    # Nothing calls this, so sema never checks its body.
    first<T>(box: Box<T>): T {
        var copy = Box<T>.make(box.get());
        var inner = copy.get();
        var count = sizes.count;
        var (a, b) = (count, inner);
        return copy.get<T>();
    }
}
"#;

/// In a generic body nothing instantiates, locals are typed from their
/// initializers and members are found by those types: a static call on a
/// generic type, a method's result, a runtime type's method, destructuring,
/// and a type argument written in a call.
#[test]
fn a_generic_body_nothing_instantiates() {
    let (uri, text, program) = load("uninstantiated", UNINSTANTIATED, "main.pep");
    let h = hover(&uri, &text, &program, at(&text, "var copy", 0, 4));
    assert!(h.starts_with("`copy` — `Box<T>`"), "{}", h);
    let make = at(&text, ".make(box", 0, 1);
    let h = hover(&uri, &text, &program, make);
    assert!(h.starts_with("`make` — `static make(value: T): Box<T>`"), "{}", h);
    assert!(definition(&uri, &text, &program, make).1.starts_with("make(value"));
    assert!(hover(&uri, &text, &program, at(&text, "inner", 0, 0)).starts_with("`inner` — `T`"));
    assert!(definition(&uri, &text, &program, at(&text, "copy.get()", 0, 5)).1.starts_with("get(): T"));
    // A member of a runtime type.
    let (file, rest) = definition(&uri, &text, &program, at(&text, "sizes.count", 0, 6));
    assert_eq!(file, "runtime/array.pep");
    assert!(rest.starts_with("count: ulong"), "{}", rest);
    assert!(hover(&uri, &text, &program, at(&text, "count = ", 0, 0)).starts_with("`count` — `ulong`"));
    assert!(hover(&uri, &text, &program, at(&text, "var (a, b)", 0, 8)).starts_with("`b` — `T`"));
    // The type argument of a call.
    let t = at(&text, "get<T>", 0, 4);
    assert!(hover(&uri, &text, &program, t).starts_with("`T` — `type parameter`"));
    assert!(definition(&uri, &text, &program, t).1.starts_with("T>(box"));
}

/// A tuple's labels hover and go to where the tuple type writes them.
#[test]
fn tuple_labels() {
    let main = r#"position(): (line: int, column: int) {
    return (line: 3, column: 7);
}
test(): int {
    var p = position();
    return p.column;
}
"#;
    let (uri, text, program) = load("tuple_labels", main, "main.pep");
    let column = at(&text, "p.column", 0, 2);
    assert!(hover(&uri, &text, &program, column).starts_with("`.column` — `int`"));
    assert!(definition(&uri, &text, &program, column).1.starts_with("column: int)"));
    assert!(hover(&uri, &text, &program, at(&text, "line: 3", 0, 0)).starts_with("`line` — `int`"));
}
/// `String.format`, which the parser lowers, and names reached in a trait's
/// default method and through an extension's bounds.
#[test]
fn lowered_calls_trait_defaults_and_bounds() {
    let main = r#"trait Named {
    name(): String;
    shout(): String { return name() + "!"; }
}
struct Box<T> {
    var item: T;
    construct(item: T) { this.item = item; }
}
extend Box<T: Named> {
    label(): String { return item.name(); }
}
test(): String {
    var a = 2;
    return String.format("{1} {0}", a, "x");
}
"#;
    let (uri, text, program) = load("lowered_calls", main, "main.pep");
    assert!(definition(&uri, &text, &program, at(&text, "name() +", 0, 0)).1.starts_with("name(): String;"));
    assert!(definition(&uri, &text, &program, at(&text, "item.name", 0, 5)).1.starts_with("name(): String;"));
    let format = at(&text, "format(", 0, 0);
    assert!(hover(&uri, &text, &program, format).starts_with("`format` — `static format("));
    assert_eq!(definition(&uri, &text, &program, at(&text, "String.format", 0, 0)).0, "runtime/string.pep");
    let h = hover(&uri, &text, &program, at(&text, ", a,", 0, 2));
    assert!(h.starts_with("`a` — `int`"), "{}", h);
}

/// A closure parameter named like the receiver of the call it is passed to
/// types from the callee, without typing itself again.
#[test]
fn a_closure_parameter_shadowing_its_receiver() {
    let main = r#"struct Node {
    visit(f: (Node) => void) { f(this); }
}
walk<T>(node: Node) {
    node.visit((node) => { var inner = node; });
}
"#;
    let (uri, text, program) = load("closure_shadowing", main, "main.pep");
    let h = hover(&uri, &text, &program, at(&text, "(node) =>", 0, 1));
    assert!(h.starts_with("`node` — `Node`"), "{}", h);
}

const RESIZED: &str = r#"struct Window {
    var width: int;
    var height: int;

    construct(this.width = 0, this.height = 0) {}

    [Alias("w", "width")]
    resize(width: int, height: int) {
        this.width = width;
        this.height = height;
    }
}

[Alias("count", "times")]
repeat(text: String, times: int): String { return text; }

main(): int {
    var window = Window(640, 480);
    window.resize(800, height = 600);
    var size = 4;
    var s = repeat("ab", size);
    return 0;
}
"#;

#[test]
fn inlay_hints_name_literal_arguments() {
    let (_, text, program) = load("parameter_hints", RESIZED, "main.pep");
    let sema = sema_model_of(&program).expect("sema");
    let hints: Vec<(Position, String)> = parameter_hints(&text, &sema)
        .into_iter()
        .map(|h| match h.label {
            InlayHintLabel::String(label) => (h.position, label),
            other => panic!("{other:?}"),
        })
        .collect();
    let position = |needle: &str| byte_to_lsp_pos(&text, at(&text, needle, 0, 0));
    // A named argument and a variable need no hint.
    assert_eq!(hints, vec![
        (position("640"), "width:".to_string()),
        (position("480"), "height:".to_string()),
        (position("800"), "width:".to_string()),
        (position("\"ab\""), "text:".to_string()),
    ]);
}

#[test]
fn completion_in_an_argument_list_offers_parameter_names() {
    let uri = Url::parse("file:///t.pep").unwrap();
    let labels = |text: &str, offset: usize| -> Vec<(String, Option<String>)> {
        let service = analyzed_server(&uri, text);
        service.inner().argument_names(&uri, text, offset).into_iter().map(|i| (i.label, i.insert_text)).collect()
    };
    let named = |names: &[&str]| -> Vec<(String, Option<String>)> {
        names.iter().map(|n| (n.to_string(), Some(format!("{} = ", n)))).collect()
    };
    // A method, after a named argument: its other parameter and the alias.
    let text = RESIZED.replace("window.resize(800, height = 600)", "window.resize(height = 600, )");
    assert_eq!(labels(&text, at(&text, ", )", 0, 2)), named(&["width", "w"]));
    // A free function, while its first argument is typed.
    let text = RESIZED.replace("repeat(\"ab\", size)", "repeat(te)");
    assert_eq!(labels(&text, at(&text, "te)", 0, 2)), named(&["text", "times", "count"]));
    // A constructor.
    let text = RESIZED.replace("Window(640, 480)", "Window()");
    assert_eq!(labels(&text, at(&text, "Window()", 0, 7)), named(&["width", "height"]));
    // Not inside an argument.
    assert!(labels(RESIZED, at(RESIZED, "640", 0, 2)).is_empty());
}

/// Names inside a property's accessor bodies resolve like a method's: a
/// local, a sibling member, the `set` accessor's `value`, and a property read
/// from outside goes to its declaration.
#[test]
fn property_accessor_bodies_resolve() {
    let main = r#"struct Account {
    var _cents: long;
    var dollars: long {
        get {
            var whole = _cents;
            return whole / 100;
        }
        set {
            _cents = value * 100;
        }
    }
}
test(): int {
    var a = Account();
    a.dollars = 3;
    return a.dollars as int;
}
"#;
    let (uri, text, program) = load("property_accessors", main, "main.pep");
    let h = hover(&uri, &text, &program, at(&text, "whole /", 0, 0));
    assert!(h.starts_with("`whole` — `long`"), "{}", h);
    assert!(definition(&uri, &text, &program, at(&text, "_cents;", 0, 0)).1.starts_with("_cents: long"));
    let h = hover(&uri, &text, &program, at(&text, "value *", 0, 0));
    assert!(h.starts_with("`value` — `long`"), "{}", h);
    let (_, rest) = definition(&uri, &text, &program, at(&text, "dollars as", 0, 0));
    assert!(rest.starts_with("dollars: long"), "{}", rest);
}
