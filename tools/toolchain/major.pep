# The major version a dependency's version range starts in. When a
# project's graph holds several majors of one package, `pepper package`
# checks each out on its own (`<name>@v<major>` in `.pep/deps`), and the
# compiler finds each dependent's copy by the major its range starts in.

## Returns the major version the version range `range` starts in: the
## first number of its lower bound (`1` for `1.4`, `^1.2` and `>=1.0, <3`),
## or for a 0.x version `0.` and its minor (`0.4` for `0.4.2`), since a
## 0.x release's minor is its major. Empty when the range has no lower
## bound (`*`, `<2`) or a wildcard minor of 0 (`0.x`).
##
## @param range a version range as pep.toml writes it
## @returns the major, or empty
export range_major(range: String): String {
    for (var comparison in range.split(",")) {
        var text = comparison.trim();
        if (text.starts_with("<") or text.starts_with("*")) {
            continue;
        }
        # `>=` before `>` and `=`.
        for (var operator in [">=", ">", "^", "~", "="]) {
            if (text.starts_with(operator)) {
                text = text.substr(operator.length, text.length).trim();
                break;
            }
        }
        var parts = text.split(".");
        var major = ulong.parse(parts[0]);
        if (major.is_empty()) {
            return "";
        }
        if (major.value() > 0) {
            return to_string(major.value());
        }
        var minor = parts.count > 1 ? ulong.parse(parts[1]) : Optional<ulong>.Value(0);
        return minor.is_value() ? $"0.{minor.value()}" : "";
    }
    return "";
}
