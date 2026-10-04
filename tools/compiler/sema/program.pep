## The linked program's model: `merge` in `crates/pepper-sema/src/program.rs`
## in Pepper. Builds each file's model and joins them into one, then writes
## it as `pep-build --emit-model` prints it.

import [render_all, Diagnostic] from compiler.diagnostic;
import json;
import [JsonValue] from json;
import compiler.link;
import [Program] from compiler.link;
import [build_file] from "builder";
import [ExtensionScopes, Module, VariableDef] from "model";

## Checks `program`, then builds the model of each of its files and joins
## them: one module, its globals ordered so a file's come after those of
## the files it imports. Members the passes synthesize come later.
##
## @param program the linked program
## @returns the model, or the rendered errors
export merge(program: Program): Result<Module, String> {
    var errors = program.check();
    if (errors.is_value()) {
        return Result<Module, String>.Err(errors.value());
    }
    var out = Module(linked = true, extension_scopes = _extension_scopes(program));
    for (var (name, groups) in program.overload_unions) {
        out.overload_unions[name] = groups;
    }
    for (var file in program.files) {
        out.namespaces.append(file.namespace);
    }
    ulong i = 0;
    while (i < program.files.count) {
        var built = build_file(program.files[i].module, i as uint);
        if (built.is_err()) {
            return Result<Module, String>.Err(render_all([built.error()], program.sources()));
        }
        _join(out, built.value());
        i += 1;
    }
    # Globals are initialized in declaration order: put each file's after
    # those of the files it depends on, so an initializer may use them.
    var rank = Array<ulong>();
    for (var _ in program.files) {
        rank.append(0);
    }
    ulong position = 0;
    for (var file in initialization_order(program)) {
        rank[file] = position;
        position += 1;
    }
    out.globals.sort((a: VariableDef, b: VariableDef) => {
        var left = _rank_of(rank, a);
        var right = _rank_of(rank, b);
        return left < right ? -1 : (left > right ? 1 : 0);
    });
    return Result<Module, String>.Ok(out);
}

## Returns the order the files' globals are initialized in: each file after
## the files it imports, the prelude's first, from the last prelude file.
##
## @param program the linked program
## @returns each file's index, once
export initialization_order(program: Program): ulong[] {
    var count = program.files.count;
    var visited = Array<bool>();
    for (var _ in program.files) {
        visited.append(false);
    }
    var roots = Array<ulong>();
    ulong i = count;
    while (i > 0) {
        i -= 1;
        if (program.files[i].prelude) {
            roots.append(i);
        }
    }
    i = 0;
    while (i < count) {
        roots.append(i);
        i += 1;
    }
    # A post-order walk over the imports, with an explicit stack of (file,
    # next import) so deep import chains do not recurse.
    var order = Array<ulong>();
    for (var root in roots) {
        if (visited[root]) {
            continue;
        }
        visited[root] = true;
        var stack = Array<(ulong, ulong)>();
        stack.append((root, 0));
        while (stack.count > 0) {
            var (file, next) = stack[stack.count - 1];
            var imports = program.files[file].imports;
            if (next >= imports.count) {
                stack.pop();
                order.append(file);
                continue;
            }
            stack[stack.count - 1] = (file, next + 1);
            var target = imports[next];
            if (target.is_value() and !visited[target.value()]) {
                visited[target.value()] = true;
                stack.append((target.value(), 0));
            }
        }
    }
    return order;
}

_rank_of(rank: ulong[], global: VariableDef): ulong {
    var file = global.loc.file as ulong;
    return file < rank.count ? rank[file] : 0;
}

## The extensions each file sees, the prelude's files, and each file's
## module.
_extension_scopes(program: Program): ExtensionScopes {
    var out = ExtensionScopes();
    ulong i = 0;
    while (i < program.files.count) {
        if (program.files[i].prelude or program.files[i].prelude_part) {
            out.prelude.insert(i as uint);
        }
        i += 1;
    }
    # Each file's module: the index of its module's first file, or none
    # outside any module.
    for (var file in program.files) {
        uint? module = Optional<uint>.Empty;
        if (file.module_root.is_value()) {
            var root = file.module_root.value().to_string();
            ulong j = 0;
            while (j < program.files.count) {
                var other = program.files[j].module_root;
                if (other.is_value() and other.value().to_string() == root) {
                    module = Optional<uint>.Value(j as uint);
                    break;
                }
                j += 1;
            }
        }
        out.module.append(module);
    }
    for (var scope in program.scopes) {
        var visible = HashSet<uint>();
        for (var extension in scope.extensions) {
            visible.insert(extension as uint);
        }
        out.visible.append(visible);
    }
    return out;
}

## Appends `other`'s declarations to `module`'s, as `Module::merge` does.
_join(module: Module, other: Module) {
    module.imports.append_all(other.imports);
    module.structs.append_all(other.structs);
    module.enums.append_all(other.enums);
    module.traits.append_all(other.traits);
    module.extensions.append_all(other.extensions);
    module.functions.append_all(other.functions);
    for (var at in other.private_functions) {
        module.private_functions.insert(at);
    }
    for (var at in other.file_private_functions) {
        module.file_private_functions.insert(at);
    }
    module.externs.append_all(other.externs);
    module.globals.append_all(other.globals);
    module.static_blocks.append_all(other.static_blocks);
    module.struct_specs.append_all(other.struct_specs);
    module.func_specs.append_all(other.func_specs);
    module.type_aliases.append_all(other.type_aliases);
    module.withheld.append_all(other.withheld);
    module.properties.append_all(other.properties);
    module.literal_args.append_all(other.literal_args);
    var offset = module.use_contexts.count;
    module.use_contexts.append_all(other.use_contexts);
    for (var use in other.type_uses) {
        use.context += offset;
        module.type_uses.append(use);
    }
    module.linked = module.linked or other.linked;
}

## Returns `module` as `pep-build --emit-model` prints it: compact JSON with
## every object's keys sorted, and the sets (`private_functions`,
## `file_private_functions` and the extension scopes) sorted, numbers by value and the rest by their text.
##
## @param module the model
## @returns the text
export model_json(module: Module): String {
    var value = module.to_json();
    var object = value.as_object().value();
    _sort_set(object["private_functions"]);
    _sort_set(object["file_private_functions"]);
    var scopes = object["extension_scopes"].as_object().value();
    _sort_set(scopes["prelude"]);
    match (scopes["visible"]) {
        Array(sets) => {
            for (var set in sets) {
                _sort_set(set);
            }
        }
        else => {}
    }
    return canonical_json(value);
}

_sort_set(set: JsonValue) {
    match (set) {
        Array(items) => {
            items.sort((a: JsonValue, b: JsonValue) => {
                if (a is Integer(_) and b is Integer(_)) {
                    var x = a.as_int().value();
                    var y = b.as_int().value();
                    return x < y ? -1 : (x > y ? 1 : 0);
                }
                return canonical_json(a).compare(canonical_json(b));
            });
        }
        else => {}
    }
}

## A step of `canonical_json`: a value to write, or text.
enum _Step {
    Value(value: JsonValue),
    Text(text: String),
}

## Returns `value` as compact JSON, as serde_json writes it: object keys
## sorted by their bytes, and numbers as Rust's `ryu` lays them out (`1.0`,
## `1e+20`, `1.5e-7`; `null` for one that is not finite).
##
## @param value the value
## @returns the text
export canonical_json(value: JsonValue): String {
    var out = Array<String>();
    var steps = Array<_Step>();
    steps.append(_Step.Value(value));
    while (steps.count > 0) {
        var step = steps.pop();
        match (step) {
            Text(text) => {
                out.append(text);
            }
            Value(v) => {
                match (v) {
                    Array(items) => {
                        out.append("[");
                        steps.append(_Step.Text("]"));
                        ulong i = items.count;
                        while (i > 0) {
                            i -= 1;
                            steps.append(_Step.Value(items[i]));
                            if (i > 0) {
                                steps.append(_Step.Text(","));
                            }
                        }
                    }
                    Object(members) => {
                        out.append("{");
                        steps.append(_Step.Text("}"));
                        var keys = Array<String>();
                        for (var (key, _) in members.iterate()) {
                            keys.append(key);
                        }
                        keys.sort((a: String, b: String) => a.compare(b));
                        ulong i = keys.count;
                        while (i > 0) {
                            i -= 1;
                            steps.append(_Step.Value(members.get(keys[i])));
                            steps.append(_Step.Text($"{JsonValue.String(keys[i]).to_string()}:"));
                            if (i > 0) {
                                steps.append(_Step.Text(","));
                            }
                        }
                    }
                    Number(number) => {
                        out.append(ryu_text(number));
                    }
                    else => {
                        out.append(v.to_string());
                    }
                }
            }
        }
    }
    return "".join(out);
}

## Returns `value` as Rust's `ryu` writes a `f64`: the shortest digits that
## read back as it, in plain notation when its decimal exponent is within
## -5 to 16 (`1.0`, `0.001`), else in scientific notation (`1e+20`,
## `1.5e-7`); `null` when it is not finite, as serde_json writes it.
##
## @param value the number
## @returns the text
export ryu_text(value: double): String {
    var shortest = _shortest_digits(value);
    if (!shortest.is_value()) {
        return "null";
    }
    var (sign, digits, exponent) = shortest.value();
    if (digits == "0") {
        return $"{sign}0.0";
    }
    var length = digits.size as long;
    var kk = length + exponent;
    if (exponent >= 0 and kk <= 16) {
        return $"{sign}{digits}{"0".repeat(exponent as ulong)}.0";
    }
    if (kk > 0 and kk <= 16) {
        var head = digits.substr_bytes(0, kk as ulong);
        return $"{sign}{head}.{digits.substr_bytes(kk as ulong, digits.size - kk as ulong)}";
    }
    if (kk > -5 and kk <= 0) {
        return $"{sign}0.{"0".repeat((-kk) as ulong)}{digits}";
    }
    var power = kk > 0 ? $"+{kk - 1}" : $"{kk - 1}";
    if (length == 1) {
        return $"{sign}{digits}e{power}";
    }
    return $"{sign}{digits.substr_bytes(0, 1)}.{digits.substr_bytes(1, digits.size - 1)}e{power}";
}

## The shortest decimal digits that read back as `value`, without leading
## or trailing zeros ("0" for zero), with its sign ("-" or "") and the
## decimal exponent of the last digit; none when `value` is not finite.
_shortest_digits(value: double): (String, String, long)? {
    var text = _float_text(value, false);
    if (text == "nan" or text == "inf" or text == "-inf") {
        return Optional<(String, String, long)>.Empty;
    }
    var sign = "";
    if (text.starts_with("-")) {
        sign = "-";
        text = text.substr_bytes(1, text.size - 1);
    }
    # The digits and the exponent of the last one.
    long exponent = 0;
    var split = text.split_once("e");
    if (split.is_value()) {
        var (mantissa, power) = split.value();
        text = mantissa;
        var positive = power.replace("+", "");
        exponent = _parse_long(positive);
    }
    var digits = "";
    var point = text.find(".");
    if (point >= 0) {
        var whole = text.substr_bytes(0, point as ulong);
        var fraction = text.substr_bytes((point + 1) as ulong, text.size - (point + 1) as ulong);
        digits = whole + fraction;
        exponent -= fraction.size as long;
    } else {
        digits = text;
    }
    while (digits.size > 1 and digits.starts_with("0")) {
        digits = digits.substr_bytes(1, digits.size - 1);
    }
    while (digits.size > 1 and digits.ends_with("0")) {
        digits = digits.substr_bytes(0, digits.size - 1);
        exponent += 1;
    }
    return Optional<(String, String, long)>.Value((sign, digits, exponent));
}

## Returns `value` as Rust's `Display` writes a `f64`: the shortest digits
## that read back as it, always in plain notation, with no `.0` for a whole
## number (`1`, `0.5`, `100000000000000000000`); `NaN`, `inf` and `-inf`
## for the special values.
##
## @param value the number
## @returns the text
export display_float(value: double): String {
    if (value != value) {
        return "NaN";
    }
    var shortest = _shortest_digits(value);
    if (!shortest.is_value()) {
        return value > 0.0 ? "inf" : "-inf";
    }
    var (sign, digits, exponent) = shortest.value();
    if (digits == "0") {
        return $"{sign}0";
    }
    var kk = digits.size as long + exponent;
    if (exponent >= 0) {
        return $"{sign}{digits}{"0".repeat(exponent as ulong)}";
    }
    if (kk > 0) {
        return $"{sign}{digits.substr_bytes(0, kk as ulong)}.{digits.substr_bytes(kk as ulong, digits.size - kk as ulong)}";
    }
    return $"{sign}0.{"0".repeat((-kk) as ulong)}{digits}";
}

_parse_long(text: String): long {
    long out = 0;
    var negative = text.starts_with("-");
    for (var c in text) {
        if (c != "-") {
            out = out * 10 + (c.byte_at(0) - '0' as byte) as long;
        }
    }
    return negative ? -out : out;
}
