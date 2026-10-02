# JSON: change a JSONC settings file and write it back with its comments.
import json;

main(): int {
    var text = "{\n  // Spaces per level.\n  \"tab_size\": 4,\n  \"font\": \"Mono\", // the editor's\n  \"wrap\": true\n}";
    var parsed = json.parse_document(text, path = "settings.json");
    if (parsed.is_err()) {
        print(parsed.error().to_string());
        return 1;
    }
    var document = parsed.value();
    assert(document.to_string() == text, "unchanged text comes back as it was");

    # Change the value; each comment stays with its value.
    document.root["tab_size"] = json.JsonValue.Integer(2);
    document.set_comments("$.wrap", ["// Wrap long lines."]);
    assert(document.comments("$.tab_size")[0] == "// Spaces per level.", "by path");
    print(document.to_string());
    # {
    #   // Spaces per level.
    #   "tab_size": 2,
    #   "font": "Mono", // the editor's
    #   // Wrap long lines.
    #   "wrap": true
    # }
    return 0;
}
