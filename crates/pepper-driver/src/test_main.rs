//! `pep-build --test`: the `main` a test build adds to the entry file.
//!
//! A test build defines the build option `TEST`, which keeps the `[Test]`
//! functions every other build drops (`passes::platform::keep`), loads the
//! runtime's `testing` module into every file, and appends to the entry
//! file's text a `main` that registers each of the file's `[Test]`
//! functions with a `TestRunner`:
//!
//! ```text
//! [TestMain]
//! main(args: String[]): int {
//!     var _pep_tests = TestRunner("math_test.pep");
//!     _pep_tests.add("adds", adds, 4);
//!     _pep_tests.add_should_panic("divides_by_zero", divides_by_zero, 9, "division by zero");
//!     return _pep_tests.run(args);
//! }
//! ```
//!
//! The text goes into the entry file itself, after its last line, so it
//! can name the file's private functions and every location before it
//! stays where it was. `[TestMain]` makes it replace the file's own `main`
//! (`passes::entry_point::lower_main_arguments`).

use pepper_parser::ast::{Declaration, Expression, Literal};
use pepper_sema::passes::platform::{SHOULD_PANIC_ATTRIBUTE, TEST_ATTRIBUTE};
use pepper_sema::program::Root;

/// The module a test build loads into every file, which declares
/// `TestRunner` and `[TestMain]`.
pub const TESTING_MODULE: &str = "testing";

/// Append the test `main` to `root`'s text. A file that does not parse is
/// left as it is, for loading to report the error where it is.
pub fn add_test_main(root: &mut Root) {
    let Ok(module) = pepper_parser::parser::parse_source_diag(&root.source) else {
        return;
    };
    let mut registrations = String::new();
    for declaration in &module.declarations {
        let Declaration::Function(function) = declaration else {
            continue;
        };
        if !function.attributes.iter().any(|a| a.name() == Some(TEST_ATTRIBUTE)) {
            continue;
        }
        let line = root.source[..function.name_span.start].matches('\n').count() + 1;
        let name = &function.name;
        let should_panic = function.attributes.iter().find(|a| a.name() == Some(SHOULD_PANIC_ATTRIBUTE));
        match should_panic {
            None => registrations.push_str(&format!("    _pep_tests.add({}, {}, {});\n", quoted(name), name, line)),
            Some(attribute) => {
                // `[ShouldPanic("text")]` or `[ShouldPanic(message = "text")]`;
                // sema reports any other argument.
                let message = attribute
                    .arguments()
                    .into_iter()
                    .find_map(|argument| match argument.value {
                        Expression::Literal { value: Literal::String(text), .. } => Some(text.clone()),
                        _ => None,
                    })
                    .unwrap_or_default();
                registrations.push_str(&format!(
                    "    _pep_tests.add_should_panic({}, {}, {}, {});\n",
                    quoted(name),
                    name,
                    line,
                    quoted(&message)
                ));
            }
        }
    }
    let file = quoted(&root.path.to_string_lossy());
    if !root.source.ends_with('\n') {
        root.source.push('\n');
    }
    root.source.push_str(&format!(
        "\n# Added by pep-build --test: runs this file's [Test] functions.\n\
         [TestMain]\n\
         main(args: String[]): int {{\n\
         \x20   var _pep_tests = TestRunner({file});\n\
         {registrations}\
         \x20   return _pep_tests.run(args);\n\
         }}\n"
    ));
}

/// `text` as a Pepper string literal.
fn quoted(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn with_main(source: &str) -> String {
        let mut root = Root { name: "t.pep".to_string(), source: source.to_string(), path: "t.pep".into() };
        add_test_main(&mut root);
        root.source
    }

    #[test]
    fn registers_each_test_with_its_line() {
        let text = with_main("[Test]\nfirst() {}\n\n[Test]\n[ShouldPanic(\"out of \\\"range\\\"\")]\nsecond() {}\n");
        assert!(text.contains("_pep_tests.add(\"first\", first, 2);"), "{}", text);
        assert!(text.contains("_pep_tests.add_should_panic(\"second\", second, 6, \"out of \\\"range\\\"\");"), "{}", text);
        assert!(text.contains("TestRunner(\"t.pep\")"), "{}", text);
    }

    #[test]
    fn leaves_a_file_that_does_not_parse() {
        assert_eq!(with_main("main( {"), "main( {");
    }
}
