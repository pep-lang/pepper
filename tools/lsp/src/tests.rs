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
    ("util.pep", "export twice(x: int): int { return x * 2; }\nstruct Tally { var n: int; }\n## Counts; ask jane@corp.com.\nexport tally(): Tally { return Tally(); }\n"),
];

/// Write `GEOMETRY` plus `main` (as `main.pep`) under a fresh directory for
/// `test`, and load the program rooted at `root` (a path in the tree).
fn load(test: &str, main: &str, root: &str) -> (Url, String, Program) {
    let dir = std::env::temp_dir().join(format!("pepper_lsp_{}", test));
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
    match PepperLsp::hover_at(uri, text, Some(program), offset).map(|h| h.contents) {
        Some(HoverContents::Markup(m)) => m.value,
        other => panic!("no hover at {}: {:?}", offset, other),
    }
}

/// The definition at `offset`: the file it is in (folder and name) and the
/// text at its range's start.
fn definition(uri: &Url, text: &str, program: &Program, offset: usize) -> (String, String) {
    let locations = PepperLsp::definition_at(uri, text, Some(program), offset).expect("a definition");
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
    int Count;

    ## Adds `by` to the count.
    ##
    ## @param by the amount to add
    ## @returns the new count
    int add(int by) {
        Count = Count + by;
        return Count;
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
    return double_it(c.Count);
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
    let field = hover(&uri, &text, &program, at(&text, "c.Count", 0, 3));
    assert!(field.contains("How many so far."), "{}", field);
}

#[test]
fn deprecated_new_offers_a_quick_fix() {
    let uri = Url::parse("file:///t.pep").unwrap();
    let text = "struct S {\n    int x;\n    new(this.x = 1) {}\n}\n";
    let fixes = |text: &str, range| quick_fixes(&uri, text, &document_warnings(text, None), range);
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
    let warnings = document_warnings(&text, Some(&program));
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
