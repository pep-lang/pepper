//! `static` blocks, the `reflect` functions and `[Attribute]` structs
//! (docs/src/language/reflection.md).

use crate::support::{compile_error, jit_census, sema};

/// A JSON-style encoder that recurses into struct fields: each
/// specialization's block emits calls that need further specializations.
#[test]
fn encodes_nested_structs_without_leaking() {
    let source = r#"
struct Inner {
    var count: int;
    var on: bool;
}

struct Outer {
    var name: String;
    var inner: Inner;
    var size: int;
}

encode<T>(value: T): String {
    var out = StringBuilder();
    out.append("{");
    static (out, value) {
        for (var field in reflect.properties<T>()) {
            out.append($"\"{field.name}\":");
            if (reflect.is_same<field.Type, String>()) {
                out.append($"\"{field.get(value)}\"");
            } else if (reflect.is_struct<field.Type>()) {
                out.append(encode(field.get(value)));
            } else {
                out.append($"{field.get(value)}");
            }
            if (!field.is_last) {
                out.append(",");
            }
        }
    }
    out.append("}");
    return out.to_string();
}

test(): int {
    var o = Outer();
    o.name = "a";
    o.inner = Inner();
    o.inner.count = 7;
    o.size = 2;
    var text = encode(o);
    if (text != "{\"name\":\"a\",\"inner\":{\"count\":7,\"on\":false},\"size\":2}") {
        print(text);
        return 1;
    }
    return 0;
}
"#;
    assert_eq!(jit_census(source), (0, 0));
}

#[test]
fn attribute_values_bind_arguments_defaults_and_names() {
    let source = r#"
enum Kind { Flag, Value }

[Attribute]
struct Option {
    const long_name: String;
    const short_name: String;
    const kind: Kind;
    const count: int = 1;

    construct(long_name: String, short_name: String = "", kind: Kind = Kind.Value) {
        this.long_name = long_name;
        this.short_name = short_name;
        this.kind = kind;
    }
}

[Attribute]
struct Marker {
    const weight: int = 5;
    const label: String = "none";
}

struct Options {
    [Option("output", "o")]
    var output: String;
    [Option("verbose", kind = Kind.Flag)]
    var verbose: bool;
    [Marker(label = "x" + "y")]
    var plain: int;
}

test(): int {
    var result = "";
    static (result) {
        for (var field in reflect.properties<Options>()) {
            if (field.has_attribute<Option>()) {
                var option = field.attribute<Option>();
                result = result + $"{option.long_name}/{option.short_name}/{option.kind == Kind.Flag}/{option.count};";
            }
            if (field.has_attribute<Marker>()) {
                result = result + $"{field.attribute<Marker>().weight}{field.attribute<Marker>().label};";
            }
        }
    }
    return result == "output/o/false/1;verbose//true/1;5xy;" ? 0 : 1;
}
"#;
    assert_eq!(jit_census(source), (0, 0));
}

#[test]
fn properties_list_public_members_and_fields_list_storage() {
    let source = r#"
struct Box {
    var _secret: int = 1;
    var width: int = 2;
    var area: int { get { return width * 10; } }
    var height: int { get; set; } = 3;

    names(): String {
        var all = "";
        static (all) {
            for (var field in reflect.fields<Box>()) {
                all = all + field.name + ",";
            }
        }
        return all;
    }
}

test(): int {
    var b = Box();
    var names = "";
    var total = 0;
    static (names, total, b) {
        for (var member in reflect.properties<Box>()) {
            names = names + $"{member.name}:{member.is_property}:{member.index},";
            total += member.get(b);
        }
    }
    if (names != "width:false:0,area:true:1,height:true:2,") {
        print(names);
        return 1;
    }
    if (total != 25) {
        return 2;
    }
    if (b.names() != "_secret,width,height,") {
        print(b.names());
        return 3;
    }
    return 0;
}
"#;
    assert_eq!(jit_census(source), (0, 0));
}

#[test]
fn cases_functions_and_set() {
    let source = r#"
enum Color { Red, Green = 5, Blue }

[Attribute]
struct Check {}

struct Counts {
    var a: int;
    var b: int;
    var name: String;
}

[Check]
one(): int { return 1; }

[Check]
two(): int { return 2; }

name_of(c: Color): String {
    var name = "?";
    static (c, name) {
        for (var case in reflect.cases<Color>()) {
            if (c == case.get()) {
                name = $"{case.name}={case.value}";
            }
        }
    }
    return name;
}

fill<T>(value: T, n: int) {
    static (value, n) {
        for (var field in reflect.properties<T>()) {
            if (reflect.is_same<field.Type, int>()) {
                field.set(value, n);
            }
        }
    }
}

test(): int {
    if (name_of(Color.Blue) != "Blue=6") {
        return 1;
    }
    var total = 0;
    static (total) {
        for (var check in reflect.functions_with<Check>()) {
            total += check.call();
        }
    }
    if (total != 3) {
        return 2;
    }
    var counts = Counts();
    fill(counts, 4);
    return counts.a + counts.b == 8 ? 0 : 3;
}
"#;
    assert_eq!(jit_census(source), (0, 0));
}

#[test]
fn compile_time_variables_and_conditions() {
    let source = r#"
struct P {
    var x: int;
    var y: int;
    var z: int;
}

test(): int {
    var result = 0;
    static (result) {
        var n = 0;
        for (var field in reflect.properties<P>()) {
            n += 1;
            if (field.name != "y") {
                result += n * 10;
            }
        }
        var count = reflect.properties<P>().count;
        result += count;
        reflect.assert(count == 3, "P has three fields");
    }
    return result;
}
"#;
    assert_eq!(jit_census(source), (43, 0));
}

#[test]
fn print_writes_a_note() {
    let module = sema("test(): int {\n    static {\n        reflect.print(reflect.name<String[]>());\n    }\n    return 0;\n}\n").unwrap();
    let notes = module.render_warnings();
    assert!(notes.contains("note: static print: \"Array<String>\""), "{}", notes);
}

#[test]
fn unknown_attribute() {
    assert_eq!(
        compile_error("[Optoin]\ntest(): int {\n    return 0;\n}\n"),
        "test.pep:1:2: error: unknown attribute 'Optoin'\n\
         \x20   1 | [Optoin]\n\
         \x20     |  ^~~~~~"
    );
}

#[test]
fn uncaptured_runtime_value() {
    let error = compile_error(
        "struct P {\n    var x: int;\n}\n\ntest(): int {\n    var total = 0;\n    static {\n        for (var f in reflect.properties<P>()) {\n            total += 1;\n        }\n    }\n    return total;\n}\n",
    );
    assert!(error.starts_with("test.pep:9:13: error: 'total' is a runtime value; add it to the static block's capture list"), "{}", error);
    assert!(error.contains("note: in pass 1 of 1 (member 'x')"), "{}", error);
}

#[test]
fn attribute_argument_errors() {
    let error = compile_error("[Attribute]\nstruct Name {\n    const value: String;\n}\n\n[Name(3)]\ntest(): int {\n    return 0;\n}\n");
    assert!(error.starts_with("test.pep:6:7: error: cannot use an integer for 'value' of attribute 'Name', which is a 'String'"), "{}", error);
    let error = compile_error("[Attribute]\nstruct Name {\n    const value: String;\n}\n\n[Name]\ntest(): int {\n    return 0;\n}\n");
    assert!(error.starts_with("test.pep:6:1: error: too few arguments to attribute 'Name': missing 'value'"), "{}", error);
    let error = compile_error("[Attribute]\nstruct Name {\n    const value: String[];\n}\n\ntest(): int {\n    return 0;\n}\n");
    assert!(error.contains("error: field 'value' of attribute 'Name' must be a number, 'bool', 'char', 'String' or an enum, not 'Array<String>'"), "{}", error);
}

#[test]
fn reflect_error_and_assert_fail_the_compile() {
    let error = compile_error("encode<T>(value: T) {\n    static {\n        reflect.assert(reflect.is_struct<T>(), $\"cannot encode '{reflect.name<T>()}'\");\n    }\n}\n\ntest(): int {\n    encode(3);\n    return 0;\n}\n");
    assert!(error.starts_with("test.pep:3:24: error: cannot encode 'i32'"), "{}", error);
    assert!(error.contains("note: in the static block of 'encode<i32>'"), "{}", error);
}

#[test]
fn compile_time_calls_and_emitted_members_are_errors() {
    let error = compile_error("struct P {\n    var x: int;\n}\n\ntest(): int {\n    static {\n        for (var f in reflect.properties<P>()) {\n            print(f.name);\n        }\n    }\n    return 0;\n}\n");
    assert!(error.starts_with("test.pep:8:13: error: 'print' cannot be called at compile time"), "{}", error);
    let error = compile_error("struct P {\n    var x: int;\n}\n\ntest(): int {\n    var n = 0;\n    static (n) {\n        for (var f in reflect.properties<P>()) {\n            n = f;\n        }\n    }\n    return n;\n}\n");
    assert!(error.starts_with("test.pep:9:17: error: 'f' is a compile-time member, which emitted code cannot use"), "{}", error);
}

#[test]
fn compile_time_while_break_and_continue() {
    let source = r#"
struct P {
    var a: int;
    var b: int;
    var c: int;
    var d: int;
}

test(): int {
    var total = 0;
    static (total) {
        # Powers of two below 100, emitted as one addition each.
        var n = 1;
        while (n < 100) {
            total += n;
            n = n * 2;
        }
        # Skip 'b', stop before 'd'.
        for (var field in reflect.properties<P>()) {
            if (field.name == "b") {
                continue;
            }
            if (field.name == "d") {
                break;
            }
            total += 1000;
        }
        var i = 0;
        while (true) {
            i += 1;
            if (i > 3) {
                break;
            }
            total += 10000;
        }
    }
    return total == 32127 ? 0 : total;
}
"#;
    assert_eq!(jit_census(source), (0, 0));
}

#[test]
fn compile_time_while_errors() {
    let error = compile_error("test(): int {\n    static {\n        var n = 0;\n        while (n >= 0) {\n            n += 1;\n        }\n    }\n    return 0;\n}\n");
    assert!(error.starts_with("test.pep:4:9: error: a compile-time 'while' ran 100000 times; is its condition ever false?"), "{}", error);
    let error = compile_error(
        "struct P {\n    var x: int;\n}\n\ntest(): int {\n    var n = 0;\n    static (n) {\n        for (var f in reflect.properties<P>()) {\n            if (n > 0) {\n                break;\n            }\n        }\n    }\n    return n;\n}\n",
    );
    assert!(error.starts_with("test.pep:10:17: error: 'break' in a runtime 'if' cannot leave a compile-time loop; the condition is not known while compiling"), "{}", error);
    let error = compile_error("test(): int {\n    static {\n        continue;\n    }\n    return 0;\n}\n");
    assert!(error.starts_with("test.pep:3:9: error: 'continue' in a 'static' block must be in a compile-time 'for' or 'while'"), "{}", error);
}

#[test]
fn module_scope_blocks_declare_constants() {
    let source = r#"
struct Point {
    var x: int;
    var y: int;
    var z: int;
}

enum Axis { X, Y, Z }

static {
    var count = 0;
    for (var field in reflect.properties<Point>()) {
        count += 1;
    }
    const POINT_FIELDS = count;
    const LAST_AXIS = reflect.cases<Axis>()[reflect.cases<Axis>().count - 1].get();
    const NAMED: bool = reflect.name<Point>() == "Point";
    reflect.assert(count == 3, "Point has three fields");
}

test(): int {
    if (LAST_AXIS != Axis.Z or !NAMED) {
        return 1;
    }
    return POINT_FIELDS == 3 ? 0 : 2;
}
"#;
    assert_eq!(jit_census(source), (0, 0));
}

#[test]
fn module_scope_block_errors() {
    let error = compile_error("static {\n    reflect.assert(false, \"stop\");\n}\n\ntest(): int {\n    return 0;\n}\n");
    assert!(error.starts_with("test.pep:2:20: error: stop"), "{}", error);
    let error = compile_error("var n = 0;\n\nstatic (n) {\n}\n\ntest(): int {\n    return 0;\n}\n");
    assert!(error.starts_with("test.pep:3:9: error: a module-scope 'static' block has no runtime values to capture"), "{}", error);
    let error = compile_error("struct P {\n    var x: int;\n}\n\nstatic {\n    for (var f in reflect.properties<P>()) {\n        f.get(P());\n    }\n}\n\ntest(): int {\n    return 0;\n}\n");
    assert!(error.contains("'get' emits code"), "{}", error);
    let error = compile_error("static {\n    const FIELDS = reflect.properties<String>();\n}\n\ntest(): int {\n    return 0;\n}\n");
    assert!(error.starts_with("test.pep:2:11: error: 'FIELDS' is a compile-time list, which emitted code cannot use"), "{}", error);
}
