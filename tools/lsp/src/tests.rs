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
        std::fs::write(path, text).unwrap();
    }
    let path = dir.join(root);
    let uri = Url::from_file_path(&path).unwrap();
    let text = std::fs::read_to_string(&path).unwrap();
    let deps = [dir.join("deps")];
    let setup = Setup { import_dirs: &deps, mode: Mode::Lenient, ..Default::default() };
    let program = load_program(Root { name: uri.to_string(), source: text.clone(), path }, &setup).unwrap();
    (uri, text, program)
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
    assert_eq!(error.message, "cannot copy 'Handle', which is not trivially copyable");
    let actions = quick_fixes(&uri, &text, &diagnostics, Range::new(Position::new(9, 13), Position::new(9, 13)));
    let [CodeActionOrCommand::CodeAction(action)] = actions.as_slice() else { panic!("{actions:?}") };
    assert_eq!(action.title, "Implement Copyable<Handle>");
    let edits = &action.edit.as_ref().unwrap().changes.as_ref().unwrap()[&uri];
    let [edit] = edits.as_slice() else { panic!("{edits:?}") };
    // Inserted after the struct's closing brace.
    assert_eq!(edit.range, Range::new(Position::new(5, 1), Position::new(5, 1)));
    assert!(edit.new_text.starts_with("

extend Handle with Copyable<Handle> {
    Handle copy(Copies copies) {"), "{}", edit.new_text);
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

const SHARED: &str = r#"struct Point { var x: int; }
twice(p: Point): int { return p.x * 2; }
main(): int {
    var p = Point();
    p.x = 21;
    return twice(p);
}
"#;

/// Every request on one text of a document reads one analysis, so the
/// program loads and sema runs once however many requests the editor sends;
/// an edit starts a fresh one.
#[test]
fn requests_on_one_text_share_one_analysis() {
    let (uri, text, _) = load("shared_analysis", SHARED, "main.pep");
    let (service, _) = LspService::new(PepperLsp::new);
    let server = service.inner();
    server.docs.lock().unwrap().insert(uri.as_str().to_string(), text.clone());

    let first = server.analysis(&uri).unwrap();
    let call = at(&text, "twice(p)", 0, 1);
    assert!(server.diagnostics(&uri).unwrap().is_empty());
    assert!(server.hover(&uri, call).is_some());
    let definition = server.definition(&uri, call).expect("a definition");
    assert_eq!(definition[0].range.start, Position::new(1, 0));
    let sema = first.sema_model().expect("sema") as *const SemaModule;
    let again = server.analysis(&uri).unwrap();
    assert!(Arc::ptr_eq(&first, &again), "one text, one analysis");
    assert_eq!(again.sema_model().unwrap() as *const SemaModule, sema, "sema runs once");

    let edited = text.replace("21", "4");
    server.docs.lock().unwrap().insert(uri.as_str().to_string(), edited.clone());
    let fresh = server.analysis(&uri).unwrap();
    assert!(!Arc::ptr_eq(&first, &fresh), "an edit starts a fresh analysis");
    assert_eq!(fresh.text, edited);
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

/// An imported file that changes on disk reaches the analysis of a document
/// that imports it once the server hears of the change, though the
/// document's own text is unchanged.
#[test]
fn a_changed_import_refreshes_the_analysis() {
    let main = "import \"util\";\nmain(): int { return twice(2); }\n";
    let (uri, text, _) = load("changed_import", main, "main.pep");
    let (service, _) = LspService::new(PepperLsp::new);
    let server = service.inner();
    server.docs.lock().unwrap().insert(uri.as_str().to_string(), text.clone());
    let call = at(&text, "twice(2)", 0, 1);
    assert_eq!(server.definition(&uri, call).expect("a definition")[0].range.start.line, 0);

    let util = uri.to_file_path().unwrap().with_file_name("util.pep");
    let source = std::fs::read_to_string(&util).unwrap();
    // Unchanged files keep the analysis; the change reaches it without word
    // from the editor.
    let other = uri.to_file_path().unwrap().with_file_name("other.pep");
    assert!(server.forget_analyses(std::slice::from_ref(&other), false).is_empty());
    std::fs::write(&util, format!("# Moved down a line.\n{}", source)).unwrap();
    assert_eq!(server.definition(&uri, call).expect("a definition")[0].range.start.line, 1);
    // The editor's word about it drops the analysis, spelled as the editor
    // spells the path.
    let spelled = Url::from_file_path(&util).unwrap().to_string();
    let spelled = match spelled.strip_prefix("file:///").and_then(|rest| rest.split_once(':')) {
        Some((drive, rest)) if drive.len() == 1 => format!("file:///{}%3A{}", drive.to_lowercase(), rest),
        _ => spelled,
    };
    let changed = Url::parse(&spelled).unwrap().to_file_path().unwrap();
    assert_eq!(server.forget_analyses(&[changed], false), vec![uri.clone()]);
    // A new file may change what an import resolves to.
    server.definition(&uri, call);
    assert_eq!(server.forget_analyses(&[other], true), vec![uri.clone()]);
}

/// An import whose file did not load (a parse error) marks the analysis:
/// fixing that file drops it, though no loaded file changed.
#[test]
fn fixing_an_import_that_did_not_load_refreshes_the_analysis() {
    let main = "import \"broken\";\nmain(): int { return 0; }\n";
    let (uri, text, _) = load("failed_import", main, "main.pep");
    let broken = uri.to_file_path().unwrap().with_file_name("broken.pep");
    std::fs::write(&broken, "export f(): int { return 1 + ; }\n").unwrap();
    let (service, _) = LspService::new(PepperLsp::new);
    let server = service.inner();
    server.docs.lock().unwrap().insert(uri.as_str().to_string(), text.clone());
    let analysis = server.analysis(&uri).unwrap();
    analysis.program().expect("the program loads without the broken file");
    assert!(analysis.is_current());
    std::fs::write(&broken, "export f(): int { return 1; }\n# Fixed.\n").unwrap();
    assert!(!analysis.is_current(), "fixing the file that did not load makes the analysis stale");
    assert_eq!(server.forget_analyses(&[broken], false), vec![uri.clone()]);
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
