# pep-fmt over every Pepper file of the repository (`runtime/`, `tools/`,
# `tests/` and `docs/examples/`): each formats, formatting its output
# changes nothing more, and the syntax tree stays the same. The runtime's
# and the tools' files are already formatted.

import [File, Path] from io;
import [JsonValue] from json;
import compiler.parse;
import [collect_sources] from "files";
import "format";

# The files are split in parts, each a test of its own, so they run side
# by side.
[Test]
formats_every_source_file_part_1() {
    formats_sources(0);
}

[Test]
formats_every_source_file_part_2() {
    formats_sources(1);
}

[Test]
formats_every_source_file_part_3() {
    formats_sources(2);
}

[Test]
formats_every_source_file_part_4() {
    formats_sources(3);
}

const FORMAT_PARTS: ulong = 4;

# Checks every `FORMAT_PARTS`th source file of the repository, from the
# `part`th.
formats_sources(part: ulong) {
    var files = Array<Path>();
    for (var folder in ["runtime", "tools", "tests", "docs/examples"]) {
        collect_sources(Path("..").join(folder), files);
    }
    expect_true(files.count > 400, "the repository's sources are found from tools/");
    var failures = Array<String>();
    var i = part;
    while (i < files.count) {
        var failure = check_file(files[i]);
        if (failure.is_value()) {
            failures.append(failure.value());
        }
        i += FORMAT_PARTS;
    }
    for (var failure in failures) {
        print(failure);
    }
    expect_equal(failures.count, 0 as ulong);
}

# What is wrong with formatting `file`, if anything.
check_file(file: Path): String? {
    var name = file.to_string();
    var source = File.read_to_string(file);
    if (source.is_err()) {
        return Optional<String>.Value($"{name}: cannot read it");
    }
    var formatted = format_source(source.value());
    if (formatted.is_err()) {
        return Optional<String>.Value($"{name}: pep-fmt failed: {formatted.error().message}");
    }
    var again = format_source(formatted.value());
    if (again.is_err()) {
        return Optional<String>.Value($"{name}: pep-fmt cannot read its own output: {again.error().message}");
    }
    if (again.value() != formatted.value()) {
        return Optional<String>.Value($"{name}: formatting is not idempotent");
    }
    if (syntax_tree(source.value()) != syntax_tree(formatted.value())) {
        return Optional<String>.Value($"{name}: formatting changed the syntax tree");
    }
    var must_be_formatted = name.starts_with(Path("../runtime").to_string())
        or name.starts_with(Path("../tools").to_string());
    if (must_be_formatted and formatted.value() != source.value()) {
        return Optional<String>.Value($"{name}: not formatted with pep-fmt (run 'pep-fmt -w {name}')");
    }
    return Optional<String>.Empty;
}

# The syntax tree of `source` as JSON, without the places of its nodes
# and with its imports sorted, since pep-fmt sorts them.
syntax_tree(source: String): String {
    var module = parse.parse(source);
    if (module.is_err()) {
        return $"error: {module.error().message}";
    }
    var json = without_spans(module.value().to_json());
    var imports = json["imports"].as_array().value();
    var sorted = Array<String>();
    for (var item in imports) {
        sorted.append(item.to_string());
    }
    sorted.sort((a, b) => a.compare(b));
    json.remove("imports");
    return "\n".join(sorted) + "\n" + json.to_string();
}

# `value` without the places of its nodes: each span (an object of just
# `start` and `end`, wherever it is) is null.
without_spans(value: JsonValue): JsonValue {
    var members = value.as_object();
    if (members.is_value()) {
        var span = members.value();
        if (span.count == 2 and span.contains("start") and span.contains("end")) {
            return JsonValue.Null;
        }
        var out = JsonValue.object();
        for (var (key, member) in members.value()) {
            out[key] = without_spans(member);
        }
        return out;
    }
    var items = value.as_array();
    if (items.is_value()) {
        var out = JsonValue.array();
        for (var item in items.value()) {
            out.append(without_spans(item));
        }
        return out;
    }
    return value;
}
