## Writing TOML: values on one line, and tables as documents.

import "value";

# A step of `_TomlInlineWriter.write`: a value still to write, or text
# (punctuation) to append.
[Value]
enum _TomlInlineStep {
    Write(value: TomlValue),
    Text(text: String),
}

# Writes `value` as it is spelled after a key's `=`, on one line.
export _toml_write_inline(value: TomlValue): String {
    var out = StringBuilder();
    _toml_append_inline(out, value);
    return out.to_string();
}

# Appends `root` to `out` on one line. Nesting comes from the data, so the
# steps still to take live on an explicit stack rather than the call stack.
export _toml_append_inline(out: StringBuilder, root: TomlValue) {
    var steps = Array<_TomlInlineStep>();
    steps.append(_TomlInlineStep.Write(root));
    while (!steps.is_empty) {
        var step = steps.pop();
        match (step) {
            Text(text) => {
                out.append(text);
            }
            Write(value) => {
                match (value) {
                    String(text) => {
                        _toml_append_string(out, text);
                    }
                    Integer(number) => {
                        out.append($"{number}");
                    }
                    Float(number) => {
                        out.append(_toml_float(number));
                    }
                    Boolean(flag) => {
                        out.append(flag ? "true" : "false");
                    }
                    DateTime(when) => {
                        out.append(when.to_string());
                    }
                    Array(items) => {
                        if (items.is_empty) {
                            out.append("[]");
                        } else {
                            out.append("[");
                            steps.append(_TomlInlineStep.Text("]"));
                            var index = items.count;
                            while (index > 0) {
                                index = index - 1;
                                steps.append(_TomlInlineStep.Write(items[index]));
                                if (index > 0) {
                                    steps.append(_TomlInlineStep.Text(", "));
                                }
                            }
                        }
                    }
                    Table(members) => {
                        if (members.is_empty) {
                            out.append("{}");
                        } else {
                            out.append("{ ");
                            # Push the members, then reverse them, so the
                            # first is written first.
                            steps.append(_TomlInlineStep.Text(" }"));
                            var low = steps.count;
                            var first = true;
                            for (var (key, member) in members) {
                                var prefix = StringBuilder();
                                if (!first) {
                                    prefix.append(", ");
                                }
                                _toml_append_key(prefix, key);
                                prefix.append(" = ");
                                steps.append(_TomlInlineStep.Text(prefix.to_string()));
                                steps.append(_TomlInlineStep.Write(member));
                                first = false;
                            }
                            var high = steps.count - 1;
                            while (low < high) {
                                steps.swap(low, high);
                                low = low + 1;
                                high = high - 1;
                            }
                        }
                    }
                }
            }
        }
    }
}

# A float as TOML spells it: `inf`, `-inf`, `nan`, or a number with a `.`
# or an exponent, so it reads back as a float.
export _toml_float(number: double): String {
    if (number != number) {
        return "nan";
    }
    if (number - number != 0.0) {
        return number > 0.0 ? "inf" : "-inf";
    }
    var spelled = $"{number}";
    if (spelled.contains(".") || spelled.contains("e") || spelled.contains("inf") || spelled.contains("nan")) {
        return spelled;
    }
    return spelled + ".0";
}

# Whether `key` can be written bare: letters, digits, `_` and `-`.
export _toml_is_bare_key(key: String): bool {
    if (key.is_empty) {
        return false;
    }
    for (var b in key.bytes()) {
        var letter = (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || b == '_' || b == '-';
        if (!letter && !(b >= '0' && b <= '9')) {
            return false;
        }
    }
    return true;
}

# Appends `key`, bare when it can be and quoted otherwise.
export _toml_append_key(out: StringBuilder, key: String) {
    if (_toml_is_bare_key(key)) {
        out.append(key);
    } else {
        _toml_append_string(out, key);
    }
}

# Appends the dotted key of `keys`.
export _toml_append_keys(out: StringBuilder, keys: Array<String>) {
    for (var index in 0..keys.count) {
        if (index > 0) {
            out.append(".");
        }
        _toml_append_key(out, keys[index]);
    }
}

# Appends `value` as a basic string in double quotes, escaping `"`, `\` and
# the control characters. Runs of bytes that need no escape are copied
# whole.
export _toml_append_string(out: StringBuilder, value: String) {
    out.append("\"");
    var size = value.size;
    ulong start = 0;
    ulong index = 0;
    while (index < size) {
        var b = value.byte_at(index);
        if ((b >= 32 || b == '\t') && b != '"' && b != '\\' && b != 127) {
            index = index + 1;
            continue;
        }
        if (index > start) {
            out.append(value.substr_bytes(start, index - start));
        }
        if (b == '"') {
            out.append("\\\"");
        } else if (b == '\\') {
            out.append("\\\\");
        } else if (b == '\n') {
            out.append("\\n");
        } else if (b == '\r') {
            out.append("\\r");
        } else if (b == 8) {
            out.append("\\b");
        } else if (b == 12) {
            out.append("\\f");
        } else {
            out.append($"\\u{b as uint:04X}");
        }
        index = index + 1;
        start = index;
    }
    if (start == 0) {
        out.append(value);
    } else if (size > start) {
        out.append(value.substr_bytes(start, size - start));
    }
    out.append("\"");
}

# Whether `value` is written as `[[header]]` sections: a non-empty array
# whose elements are all tables.
export _toml_is_table_array(value: TomlValue): bool {
    if (value is Array(items)) {
        if (items.is_empty) {
            return false;
        }
        for (var item in items) {
            if (!(item is Table)) {
                return false;
            }
        }
        return true;
    }
    return false;
}

# A section still to write: a table, the keys of its header, and whether
# it is an element of an array of tables (`[[keys]]`).
struct _TomlSectionStep {
    OrderedMap<String, TomlValue> members;
    Array<String> keys;
    bool element;

    construct(members: OrderedMap<String, TomlValue>, keys: Array<String>, element: bool) {
        this.members = members;
        this.keys = keys;
        this.element = element;
    }
}

# Writes the table `root` as a document. Each section's plain members come
# first, then its tables and arrays of tables as sections of their own, in
# member order; the sections still to write live on an explicit stack.
export _toml_write_document(root: OrderedMap<String, TomlValue>): String {
    var out = StringBuilder();
    var steps = Array<_TomlSectionStep>();
    steps.append(_TomlSectionStep(root, Array<String>(), false));
    var wrote = false;
    while (!steps.is_empty) {
        var step = steps.pop();
        var plain = 0;
        var nested = 0;
        for (var (key, member) in step.members) {
            if (member is Table || _toml_is_table_array(member)) {
                nested = nested + 1;
            } else {
                plain = plain + 1;
            }
        }
        # A table holding only tables needs no header of its own; an empty
        # one does, or it would vanish.
        if (!step.keys.is_empty && (step.element || plain > 0 || nested == 0)) {
            if (wrote) {
                out.append("\n");
            }
            out.append(step.element ? "[[" : "[");
            _toml_append_keys(out, step.keys);
            out.append(step.element ? "]]\n" : "]\n");
            wrote = true;
        }
        for (var (key, member) in step.members) {
            if (!(member is Table) && !_toml_is_table_array(member)) {
                _toml_append_key(out, key);
                out.append(" = ");
                _toml_append_inline(out, member);
                out.append("\n");
                wrote = true;
            }
        }
        # Push the nested sections in reverse, so the first is written
        # first.
        var low = steps.count;
        for (var (key, member) in step.members) {
            var keys = step.keys.clone();
            keys.append(key);
            if (member is Table(members)) {
                steps.append(_TomlSectionStep(members, keys, false));
            } else if (_toml_is_table_array(member)) {
                for (var item in member.as_array().value()) {
                    steps.append(_TomlSectionStep(item.as_table().value(), keys, true));
                }
            }
        }
        var high = steps.count;
        while (low + 1 < high) {
            high = high - 1;
            steps.swap(low, high);
            low = low + 1;
        }
    }
    return out.to_string();
}
