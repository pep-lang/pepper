# JSON: choose how an enum's cases are written with attributes.
import json;

# A tag beside the values: {"kind": "circle", "radius": 2}.
[Tag("kind")]
enum Shape {
    [Name("circle")]
    Circle(radius: int),
    Point,
}

# The values under their own key: {"type": "Click", "data": {"x": 1, "y": 2}}.
[Tag("type", content = "data")]
enum Event {
    Click(x: int, y: int),
    Close,
}

# No tag; reading takes the first case that fits.
[Untagged]
enum Size {
    Fixed(px: int),
    Auto,
}

main(): int {
    assert(json.encode(Shape.Circle(2)) == "{\"kind\":\"circle\",\"radius\":2}", "internally tagged");
    assert(json.encode(Shape.Point) == "{\"kind\":\"Point\"}", "a case with no values");
    assert(json.encode(Event.Click(1, 2)) == "{\"type\":\"Click\",\"data\":{\"x\":1,\"y\":2}}", "adjacently tagged");
    assert(json.encode(Size.Fixed(8)) == "{\"px\":8}", "untagged");
    assert(json.encode(Size.Auto) == "\"Auto\"", "untagged, no values");

    var shape = json.decode<Shape>("{\"kind\": \"circle\", \"radius\": 5}");
    if (shape.value() is Circle(radius)) {
        assert(radius == 5, "read back");
    } else {
        return 1;
    }
    var size = json.decode<Size>("\"Auto\"");
    assert(size.value() is Auto, "the first case that fits");
    var bad = json.decode<Shape>("{\"radius\": 5}");
    assert(bad.error().to_string() == "1:1: error: $: missing tag 'kind'", "a missing tag");
    return 0;
}
