//! The `json` module's compile-time errors: types that `encode` and
//! `decode` cannot convert. Its runtime behaviour is tested by the `[Test]`
//! functions in `runtime/json/test/`.

#[test]
fn rejects_types_it_cannot_convert() {
    let error = crate::support::compile_error(
        "import json;\n\nstruct Job {\n    var name: String;\n    var outcome: Result<int>;\n}\n\ntest(): int {\n    var text = json.encode(Job());\n    return 0;\n}\n",
    );
    assert!(error.contains("error: 'encode' cannot convert property 'outcome' of type 'Result<int>' to JSON"), "{}", error);
    assert!(error.contains("test.pep:9:16: note: 'encode<Job>' is used by 'test' here"), "{}", error);
    let error = crate::support::compile_error(
        "import json;\n\nstruct Inner {\n    var handle: __ptr<void>;\n}\n\nstruct Job {\n    var inner: Inner;\n}\n\ntest(): int {\n    var job = json.decode<Job>(\"{}\");\n    return 0;\n}\n",
    );
    assert!(error.contains("error: 'decode' cannot convert property 'handle' of type"), "{}", error);
    assert!(error.contains("note: '_from_json<Inner>' is used by '_from_json<Job>' here"), "{}", error);
    assert!(error.contains("test.pep:12:15: note: 'decode<Job>' is used by 'test' here"), "{}", error);
}

#[test]
fn rejects_an_enum_tag_that_names_a_value() {
    let error = crate::support::compile_error(
        r##"
import json;

[Tag("radius")]
enum Shape {
    Circle(radius: int),
}

test(): int {
    var text = json.encode(Shape.Circle(1));
    return 0;
}
"##,
    );
    assert!(
        error.contains("'encode' cannot convert case 'Circle' of 'Shape': its value 'radius' has the name of the tag"),
        "{}",
        error
    );
}
