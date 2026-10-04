# The json module's tagged ([Tag]), adjacently tagged and untagged
# ([Untagged]) enums, and [Name] on a case.

import json;

[Tag("kind")]
private enum Shape {
    [Name("circle")]
    Circle(radius: int),
    Rect(width: int, height: int),
    Point,
}

[Tag("type", content = "data")]
enum Event {
    Click(x: int, y: int),
    Close,
}

[Untagged]
private enum Size {
    Box(width: int, height: int),
    Fixed(px: int),
    Auto,
    Fill,
}

private enum Mode {
    [Name("read-only")]
    ReadOnly,
    [Name("cmd")]
    Command(line: String),
}

struct Scene {
    var shapes: Array<Shape>;
    var events: Array<Event>;
    var sizes: Array<Size>;
    var modes: Array<Mode>;
}

shape_error(text: String): String {
    return json.decode<Shape>(text, unknown_keys = json.UnknownKeys.Reject).error().to_string();
}

event_error(text: String): String {
    return json.decode<Event>(text, unknown_keys = json.UnknownKeys.Reject).error().to_string();
}

size_error(text: String): String {
    return json.decode<Size>(text, unknown_keys = json.UnknownKeys.Reject).error().to_string();
}

[Test]
converts_tagged_and_untagged_enums() {
    var scene = Scene();
    scene.shapes = [Shape.Circle(2), Shape.Rect(3, 4), Shape.Point];
    scene.events = [Event.Click(1, 2), Event.Close];
    scene.sizes = [Size.Box(1, 2), Size.Fixed(8), Size.Auto, Size.Fill];
    scene.modes = [Mode.ReadOnly, Mode.Command("ls")];
    var text = json.encode(scene);
    var expected = "{\"shapes\":[{\"kind\":\"circle\",\"radius\":2},{\"kind\":\"Rect\",\"width\":3,\"height\":4},{\"kind\":\"Point\"}],\"events\":[{\"type\":\"Click\",\"data\":{\"x\":1,\"y\":2}},{\"type\":\"Close\"}],\"sizes\":[{\"width\":1,\"height\":2},{\"px\":8},\"Auto\",\"Fill\"],\"modes\":[\"read-only\",{\"cmd\":{\"line\":\"ls\"}}]}";
    expect_equal(text, expected);
    var decoded = json.decode<Scene>(text, unknown_keys = json.UnknownKeys.Reject);
    if (decoded.is_err()) {
        panic(decoded.error().to_string());
    }
    expect_equal(json.encode(decoded.value()), text);
    if (decoded.value().sizes[1] is Fixed(px)) {
        expect_equal(px, 8);
    } else {
        panic("decoded the wrong case");
    }
    expect_true(decoded.value().sizes[3] is Fill);

    # Untagged reads the first case that fits; extra keys skip a case only
    # when unknown keys are rejected.
    var loose = json.decode<Size>("{\"px\": 3, \"z\": 1}");
    if (loose.value() is Fixed(px)) {
        expect_equal(px, 3);
    } else {
        panic("decoded the wrong case");
    }

    expect_equal(shape_error("[]"), "1:1: error: $: expected an object, found an array");
    expect_equal(shape_error("{\"radius\": 2}"), "1:1: error: $: missing tag 'kind'");
    expect_equal(shape_error("{\"kind\": 3}"), "1:10: error: $.kind: expected a string, found a number");
    expect_equal(shape_error("{\"kind\": \"Hex\"}"), "1:10: error: $.kind: 'Hex' is not a case of 'Shape'");
    expect_equal(shape_error("{\"kind\": \"Circle\"}"), "1:10: error: $.kind: 'Circle' is not a case of 'Shape'");
    expect_equal(shape_error("{\"kind\": \"circle\"}"), "1:1: error: $: missing value 'radius'");
    expect_equal(shape_error("{\"kind\": \"circle\", \"radius\": 1, \"z\": 0}"), "1:38: error: $.z: unknown key 'z'");
    expect_equal(shape_error("{\"kind\": \"Point\", \"z\": 0}"), "1:24: error: $.z: unknown key 'z'");
    expect_equal(
        event_error("{\"type\": \"Click\", \"data\": 1}"), "1:27: error: $.data: expected an object, found a number"
    );
    expect_equal(
        event_error("{\"type\": \"Click\", \"data\": {\"x\": 1, \"y\": 2}, \"z\": 0}"),
        "1:50: error: $.z: unknown key 'z'"
    );
    expect_equal(size_error("{\"px\": \"x\"}"), "1:1: error: $: found an object, which matches no case of 'Size'");
    expect_equal(size_error("\"Huge\""), "1:1: error: $: found a string, which matches no case of 'Size'");
    expect_equal(
        size_error("{\"px\": 3, \"z\": 1}"), "1:1: error: $: found an object, which matches no case of 'Size'"
    );
}
