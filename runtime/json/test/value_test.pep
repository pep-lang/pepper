# The json module's JsonValue and JsonDocument: compact and indented
# output, editing arrays and objects, and documents that keep the comments
# of JSONC text.

import json;

[Test]
writes_compact_and_indented_text() {
    var reply = json.JsonValue.object();
    reply["id"] = json.JsonValue.Integer(42);
    reply["tags"] = json.JsonValue.array([json.JsonValue.String("a"), json.JsonValue.String("b")]);
    reply["empty"] = json.JsonValue.array();
    reply["none"] = json.JsonValue.object();
    reply["ratio"] = json.JsonValue.Number(0.5);
    reply["ok"] = json.JsonValue.Bool(false);
    reply["nothing"] = json.JsonValue.Null;
    var compact = "{\"id\":42,\"tags\":[\"a\",\"b\"],\"empty\":[],\"none\":{},\"ratio\":0.5,\"ok\":false,\"nothing\":null}";
    expect_equal(reply.to_string(), compact);
    expect_equal($"{reply}", compact);
    var pretty = "{\n  \"id\": 42,\n  \"tags\": [\n    \"a\",\n    \"b\"\n  ],\n  \"empty\": [],\n  \"none\": {},\n  \"ratio\": 0.5,\n  \"ok\": false,\n  \"nothing\": null\n}";
    expect_equal(reply.to_pretty_string(), pretty);
    var list = json.JsonValue.array([json.JsonValue.array([json.JsonValue.Integer(1)])]);
    expect_equal(list.to_pretty_string(indent = 4), "[\n    [\n        1\n    ]\n]");
    expect_equal(list.to_pretty_string(0), "[\n[\n1\n]\n]");
    # Strings escape quotes, backslashes and control characters.
    var text = json.JsonValue.String("q\"b\\n\n\t\u{1}é😀");
    expect_equal(text.to_string(), "\"q\\\"b\\\\n\\n\\t\\u0001é😀\"");
    expect_equal(text.to_string(ascii_only = true), "\"q\\\"b\\\\n\\n\\t\\u0001\\u00e9\\ud83d\\ude00\"");
    # NaN and the infinities are not JSON.
    var zero = 0.0;
    var odd = json.JsonValue.array([json.JsonValue.Number(zero / zero), json.JsonValue.Number(1.0 / zero)]);
    expect_equal(odd.to_string(), "[null,null]");
    # Text round-trips, keys in their order.
    var source = "{\"z\":1,\"a\":[true,{\"m\":\"\\u00e9\"}],\"k\":-2.5e-7}";
    var again = json.parse(json.parse(source).value().to_string()).value().to_string();
    expect_equal(again, "{\"z\":1,\"a\":[true,{\"m\":\"é\"}],\"k\":-2.5e-07}");
    expect_equal(json.parse(again).value().to_string(), again);
}

[Test]
edits_arrays_and_objects() {
    var root = json.parse("{\"list\": [1, 2], \"name\": \"a\"}").value();
    var list = root["list"];
    list.append(json.JsonValue.Integer(3));
    list[0] = json.JsonValue.String("one");
    root["name"] = json.JsonValue.String("b");
    root["added"] = json.JsonValue.Bool(true);
    expect_equal(root.to_string(), "{\"list\":[\"one\",2,3],\"name\":\"b\",\"added\":true}");
    expect_true(root.remove("name"));
    expect_false(root.remove("name"));
    expect_equal(root.to_string(), "{\"list\":[\"one\",2,3],\"added\":true}");
    # The array is held by reference: changing it changes the value.
    root["list"].as_array().value().pop();
    expect_equal(root["list"].to_string(), "[\"one\",2]");
    expect_false(json.JsonValue.Integer(1).remove("x"));
    expect_false(json.JsonValue.Null.contains("x"));
}

[Test]
keeps_the_comments_of_a_document() {
    var text = "// top\n{\n  // The editor.\n  \"tab_size\": 4, // spaces\n  \"list\": [\n    1, /* one */\n    2 // two\n  ],\n  \"empty\": {\n    // nothing\n  },\n  \"wrap\": true // last\n  // end of root\n} // after\n// tail";
    var parsed = json.parse_document(text);
    expect_false(parsed.is_err());
    var document = parsed.value();
    # Read and written unchanged, the text comes back as it was.
    expect_equal(document.to_string(), text);
    expect_equal(document.comments("$.tab_size")[0], "// The editor.");
    expect_true(document.comments("$.wrap").is_empty);
    # A changed value keeps its comments; a removed one drops them.
    document.root["wrap"] = json.JsonValue.Bool(false);
    document.root.remove("list");
    document.set_comments("$.wrap", ["/* changed */"]);
    var changed = "// top\n{\n  // The editor.\n  \"tab_size\": 4, // spaces\n  \"empty\": {\n    // nothing\n  },\n  /* changed */\n  \"wrap\": false // last\n  // end of root\n} // after\n// tail";
    expect_equal(document.to_string(), changed);
    # Unlayouted text comes out indented, comments in place.
    var compact = json.parse_document("[1, // a\n2]").value();
    expect_equal(compact.to_string(indent = 4), "[\n    1, // a\n    2\n]");
    var bad = json.parse_document("[1 /* never closed", path = "s.json");
    expect_equal(bad.error().to_string(), "s.json:1:4: error: unterminated '/*' comment");
    var plain = json.JsonDocument(json.JsonValue.Integer(1));
    expect_equal(plain.to_string(), "1");
}
