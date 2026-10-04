# The json module's conversion of enums whose cases carry values: the
# default external form, and a reference enum's empty slot.

import json;

private enum Shape {
    Circle(radius: int),
    Rect(width: int, height: double),
    Point,
}

enum Tree {
    Leaf(value: int),
    Node(left: Tree, right: Tree),
}

[Value]
private enum Size {
    Fixed(px: int),
    Auto,
}

struct Drawing {
    var shapes: Array<Shape>;
    var tree: Tree;
    var sizes: Array<Size>;
}

private error_of(text: String): String {
    return json.decode<Shape>(text, unknown_keys = json.UnknownKeys.Reject).error().to_string();
}

[Test]
converts_enums_whose_cases_carry_values() {
    var drawing = Drawing();
    drawing.shapes = [Shape.Circle(2), Shape.Rect(3, 4.5), Shape.Point];
    drawing.tree = Tree.Node(Tree.Leaf(1), Tree.Node(Tree.Leaf(2), Tree.Leaf(3)));
    drawing.sizes = [Size.Fixed(8), Size.Auto];
    var text = json.encode(drawing);
    var expected = "{\"shapes\":[{\"Circle\":{\"radius\":2}},{\"Rect\":{\"width\":3,\"height\":4.5}},\"Point\"],\"tree\":{\"Node\":{\"left\":{\"Leaf\":{\"value\":1}},\"right\":{\"Node\":{\"left\":{\"Leaf\":{\"value\":2}},\"right\":{\"Leaf\":{\"value\":3}}}}}},\"sizes\":[{\"Fixed\":{\"px\":8}},\"Auto\"]}";
    expect_equal(text, expected);
    var decoded = json.decode<Drawing>(text);
    if (decoded.is_err()) {
        panic(decoded.error().to_string());
    }
    expect_equal(json.encode(decoded.value()), text);
    if (decoded.value().shapes[1] is Rect(w, h)) {
        expect_equal(w, 3);
        expect_equal(h, 4.5);
    } else {
        panic("decoded the wrong case");
    }

    # A reference enum's empty slot is null, both ways.
    var empty = json.encode(Drawing());
    expect_equal(empty, "{\"shapes\":null,\"tree\":null,\"sizes\":null}");
    expect_true(json.decode<Drawing>(empty).value().tree === __null);

    expect_equal(
        error_of("{\"Circle\": {\"radius\": \"x\"}}"), "1:23: error: $.Circle.radius: expected a number, found a string"
    );
    expect_equal(error_of("{\"Circle\": {}}"), "1:12: error: $.Circle: missing value 'radius'");
    expect_equal(
        error_of("\"Circle\""), "1:1: error: $: case 'Circle' carries values; write it as {\"Circle\": {...}}"
    );
    expect_equal(
        error_of("{\"Point\": {}}"), "1:1: error: $: case 'Point' carries no values; write it as the string \"Point\""
    );
    expect_equal(error_of("\"Hex\""), "1:1: error: $: 'Hex' is not a case of 'Shape'");
    expect_equal(error_of("3"), "1:1: error: $: expected a string or an object with one key, found a number");
    expect_equal(error_of("{\"Circle\": {\"radius\": 1, \"z\": 2}}"), "1:31: error: $.Circle.z: unknown key 'z'");
    expect_equal(error_of("{\"Circle\": 1}"), "1:12: error: $.Circle: expected an object, found a number");
}
