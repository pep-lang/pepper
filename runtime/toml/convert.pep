## Struct conversion: `encode` and `decode` turn Pepper values into TOML
## documents and back, through reflection, with no per-type code to write.
## They read the same `serialize` attributes `json` does, so one set of
## attributes describes a type for both formats.

import serialize;
import "parse";
import "value";

## What `decode` does with a table key that names no property of the
## struct it is read into.
export enum UnknownKeys {
    ## Skips the key and its value.
    Ignore,
    ## Fails with an error naming the key and its path.
    Reject,
}

## Converts `value` to a `TomlValue`.
##
## `T` may be a number type, `bool`, `String`, `TomlDateTime`, an enum (a
## case that carries no values as its name, `"Point"`; one that carries
## values as `{ Circle = { radius = 2 } }`), `Optional<U>`, `Array<U>`, a
## map with `String` keys (`HashMap`, `OrderedMap` or `Map`) as a table,
## `TomlValue` itself, or a struct, whose public properties become a
## table's members in declaration order. Element and property types follow
## the same rules, so structs nest.
##
## TOML has no null, so what JSON writes as `null` is left out: an empty
## `Optional`, a `String` or struct property that holds no object, and such
## an element of an array or map. A `ulong` past the largest TOML integer,
## 2^63 - 1, is written as a float.
##
## A struct property takes its key from `[Name("key")]` when it has one,
## and is left out when marked `[Ignore]` (the attributes of the
## `serialize` module, which `toml` shares with `json`).
##
## The conversion is generated while compiling, by a `static` block per
## type. A type it cannot convert, such as a `Result`, is a compile error
## naming the property:
## `'encode' cannot convert property 'outcome' of type 'Result<int>' to TOML`.
##
## @typeParam T the type of the value
## @param value the value to convert
## @returns the value as TOML, or none when there is nothing to write
## @example
##     import toml;
##
##     struct Point {
##         var x: int;
##         var y: int;
##     }
##
##     main(): int {
##         var p = Point();
##         p.x = 1;
##         p.y = 2;
##         assert(toml.to_toml(p).value()["y"].as_int().value() == 2, "a member");
##         return 0;
##     }
export to_toml<T>(value: T): TomlValue? {
    return _to_toml(value);
}

## Writes `value`, a struct or a map, as a TOML document, converting it as
## `to_toml` does.
##
## @typeParam T the type of the value
## @param value the value to write
## @returns the document text
## @panics if `value` does not convert to a table, as a number or an array
##   does ("toml.encode needs a value that converts to a table")
## @example
##     import toml;
##
##     struct Package {
##         var name: String;
##         var version: String;
##         var authors: Array<String>;
##     }
##
##     struct Manifest {
##         var package: Package;
##         [Name("build-script")]
##         var build_script: String?;
##     }
##
##     main(): int {
##         var manifest = Manifest();
##         manifest.package = Package();
##         manifest.package.name = "demo";
##         manifest.package.version = "0.1.0";
##         manifest.package.authors = ["Ada"];
##         var text = toml.encode(manifest);
##         assert(text == "[package]\nname = \"demo\"\nversion = \"0.1.0\"\nauthors = [\"Ada\"]\n", "a document");
##         return 0;
##     }
export encode<T>(value: T): String {
    var root = _to_toml(value);
    if (root.is_empty() || !(root.value() is Table)) {
        panic("toml.encode needs a value that converts to a table");
    }
    return root.value().to_document();
}

## Converts a `TomlValue` to a `T`, the reverse of `to_toml`.
##
## A struct is made with its constructor that takes no arguments, then each
## property found in the table is read in. A missing key leaves its
## property at its default (an empty `Optional`, for one), unless the
## property is marked `[Required]`, which makes it an error; a property
## marked `[Ignore]` is never read. A key that names no property is
## skipped, or with `unknown_keys = UnknownKeys.Reject` is an error.
##
## An integer converts to an integer type it fits, and to `float` or
## `double`; a float converts only to `float` or `double`.
##
## An error names where in the document it is, as a path from the root `$`
## in its `value_path` and at the start of its message, and has no line or
## column, since there is no text: `$.package.version: expected a string,
## found an integer`.
##
## @typeParam T the type to convert to
## @param value the TOML value
## @param unknown_keys what to do with a key that names no property
## @returns the converted value, or the first error
export from_toml<T>(value: TomlValue, unknown_keys: UnknownKeys = UnknownKeys.Ignore): Result<T, TomlError> {
    var witness: T;
    return _from_toml(value, witness, "$", unknown_keys);
}

## Parses a TOML document and converts it to a `T`: `parse`, then
## `from_toml`.
##
## @typeParam T the type to convert to
## @param text the TOML text
## @param unknown_keys what to do with a key that names no property
## @param path the name of the text (a file name, say), which the error's
##   `to_string()` puts first
## @returns the value, or the first error: a syntax error, or a conversion
##   error with its path in the document; either has its line and column
##   when the value it is about is written in the text
## @example
##     import toml;
##
##     struct Package {
##         [Required]
##         var name: String;
##         var version: String;
##         var authors: Array<String>;
##         var edition: int?;
##     }
##
##     struct Manifest {
##         [Required]
##         var package: Package;
##     }
##
##     main(): int {
##         var text = "[package]\nname = \"demo\"\nversion = \"0.1.0\"\nauthors = [\"Ada\"]\n";
##         var manifest = toml.decode<Manifest>(text);
##         assert(manifest.value().package.name == "demo", "a string");
##         assert(manifest.value().package.authors[0] == "Ada", "an array");
##         assert(manifest.value().package.edition.is_empty(), "a missing optional");
##
##         var bad = toml.decode<Manifest>("[package]\nname = 7\n", path = "pep.toml");
##         assert(
##             bad.error().to_string() == "pep.toml:2:8: error: $.package.name: expected a string, found an integer",
##             "where"
##         );
##         return 0;
##     }
export decode<T>(
    text: String, unknown_keys: UnknownKeys = UnknownKeys.Ignore, path: String = ""
): Result<T, TomlError> {
    var parsed = parse(text, path = path);
    if (parsed.is_err()) {
        return Result<T, TomlError>.err(parsed.error());
    }
    var witness: T;
    var result = _from_toml(parsed.value(), witness, "$", unknown_keys);
    if (result.is_err()) {
        var error = result.error();
        error.path = path;
        var offset = _toml_locate(text, error.value_path);
        if (offset.is_value()) {
            _toml_place(error, text, offset.value());
        }
        return Result<T, TomlError>.err(error);
    }
    return result;
}

# ── Encoding ───────────────────────────────────────────────────────────────
#
# One overload per kind of type: overload resolution picks the most
# specialized, so `Array<T>` and `T?` take their own, and the catch-all
# `_to_toml<T>` handles numbers, enums and structs in a static block. Each
# gives none for a value TOML leaves out.

_to_toml(value: String): TomlValue? {
    if (value === __null) {
        return Optional<TomlValue>.Empty;
    }
    return Optional<TomlValue>.Value(TomlValue.String(value));
}

_to_toml(value: TomlValue): TomlValue? {
    if (value === __null) {
        return Optional<TomlValue>.Empty;
    }
    return Optional<TomlValue>.Value(value);
}

_to_toml(value: TomlDateTime): TomlValue? {
    if (value === __null) {
        return Optional<TomlValue>.Empty;
    }
    return Optional<TomlValue>.Value(TomlValue.DateTime(value));
}

_to_toml(value: bool): TomlValue? {
    return Optional<TomlValue>.Value(TomlValue.Boolean(value));
}

_to_toml<T>(value: T?): TomlValue? {
    if (value.is_value()) {
        return _to_toml(value.value());
    }
    return Optional<TomlValue>.Empty;
}

_to_toml<T>(value: Array<T>): TomlValue? {
    if (value === __null) {
        return Optional<TomlValue>.Empty;
    }
    var items = Array<TomlValue>(value.count);
    for (var element in value) {
        var item = _to_toml(element);
        if (item.is_value()) {
            items.append(item.value());
        }
    }
    return Optional<TomlValue>.Value(TomlValue.Array(items));
}

_to_toml<V>(value: HashMap<String, V>): TomlValue? {
    return _toml_table_of(value);
}

_to_toml<V>(value: OrderedMap<String, V>): TomlValue? {
    return _toml_table_of(value);
}

_to_toml<V>(value: Map<String, V>): TomlValue? {
    return _toml_table_of(value);
}

# A table of the members of `map`, any map with `String` keys.
_toml_table_of<TMap>(map: TMap): TomlValue? {
    if (map === __null) {
        return Optional<TomlValue>.Empty;
    }
    var members = OrderedMap<String, TomlValue>();
    for (var (key, member) in map) {
        var item = _to_toml(member);
        if (item.is_value()) {
            members[key] = item.value();
        }
    }
    return Optional<TomlValue>.Value(TomlValue.Table(members));
}

_to_toml<T>(value: T): TomlValue? {
    var out = Optional<TomlValue>.Empty;
    var present = true;
    # Runtime locals of the static block, which a `var` inside it would
    # make compile-time values: a struct's table, or a case's values.
    var table = TomlValue.table();
    static (out, value, present, table) {
        if (reflect.is_same<T, i8>()
            || reflect.is_same<T, i16>()
            || reflect.is_same<T, i32>()
            || reflect.is_same<T, i64>()
            || reflect.is_same<T, u8>()
            || reflect.is_same<T, u16>()
            || reflect.is_same<T, u32>()) {
            out = Optional<TomlValue>.Value(TomlValue.Integer(value as long));
        } else if (reflect.is_same<T, u64>()) {
            out = Optional<TomlValue>.Value(_toml_of_ulong(value));
        } else if (reflect.is_same<T, float>() || reflect.is_same<T, double>()) {
            out = Optional<TomlValue>.Value(TomlValue.Float(value as double));
        } else if (reflect.is_enum<T>()) {
            reflect.assert(
                !reflect.name<T>().starts_with("Result<"), $"'encode' cannot convert type '{reflect.name<T>()}' to TOML"
            );
            # A case that carries nothing is its name; one that carries
            # values is `{ Case = { value = ... } }`. A reference enum's
            # slot may hold no value, which is left out.
            if (reflect.is_reference<T>()) {
                present = _toml_holds(value);
            }
            for (var case in reflect.cases<T>()) {
                if (present && case.matches(value)) {
                    if (case.values.is_empty) {
                        out = Optional<TomlValue>.Value(TomlValue.String(case.name));
                    } else {
                        out = Optional<TomlValue>.Value(_toml_case_table(case.name, table));
                        for (var item in case.values) {
                            _toml_put(table, item.name, _to_toml(item.get(value)));
                        }
                    }
                }
            }
        } else if (reflect.is_struct<T>()) {
            present = _toml_holds(value);
            if (present) {
                out = Optional<TomlValue>.Value(table);
            }
            for (var field in reflect.properties<T>()) {
                if (field.has_attribute<serialize.Ignore>()) {
                    continue;
                }
                # A shallow check, to name the property; the types
                # inside an array or a struct are checked when they
                # are converted.
                var convertible = !field.type_name.starts_with("Result<")
                    && (reflect.is_struct<field.Type>()
                        || reflect.is_enum<field.Type>()
                        || reflect.is_same<field.Type, bool>()
                        || reflect.is_same<field.Type, i8>()
                        || reflect.is_same<field.Type, i16>()
                        || reflect.is_same<field.Type, i32>()
                        || reflect.is_same<field.Type, i64>()
                        || reflect.is_same<field.Type, u8>()
                        || reflect.is_same<field.Type, u16>()
                        || reflect.is_same<field.Type, u32>()
                        || reflect.is_same<field.Type, u64>()
                        || reflect.is_same<field.Type, float>()
                        || reflect.is_same<field.Type, double>());
                reflect.assert(
                    convertible, $"'encode' cannot convert property '{field.name}' of type '{field.type_name}' to TOML"
                );
                var key = field.name;
                if (field.has_attribute<serialize.Name>()) {
                    key = field.attribute<serialize.Name>().value;
                }
                if (present) {
                    _toml_put(table, key, _to_toml(field.get(value)));
                }
            }
        } else {
            reflect.error($"'encode' cannot convert type '{reflect.name<T>()}' to TOML");
        }
    }
    return out;
}

# An integer, or a float past the largest TOML integer.
_toml_of_ulong(value: ulong): TomlValue {
    if (value <= 9223372036854775807) {
        return TomlValue.Integer(value as long);
    }
    return TomlValue.Float(value as double);
}

# Whether a struct or enum reference holds an object.
_toml_holds<T>(value: T): bool {
    return !(value === __null);
}

# `{ name = payload }`, the form of a case that carries values.
_toml_case_table(name: String, payload: TomlValue): TomlValue {
    var table = TomlValue.table();
    table[name] = payload;
    return table;
}

# Sets member `key` of `table` to `member`, unless it is none.
_toml_put(table: TomlValue, key: String, member: TomlValue?) {
    if (member.is_value()) {
        table[key] = member.value();
    }
}

# ── Decoding ───────────────────────────────────────────────────────────────
#
# As for encoding, one overload per kind of type, picked by the type of
# `witness`: a value of the target type whose only use is choosing the
# overload (a struct's current property, or a default-initialized local).

_from_toml(
    value: TomlValue, witness: TomlValue, path: String, unknown_keys: UnknownKeys
): Result<TomlValue, TomlError> {
    return Result<TomlValue, TomlError>.ok(value);
}

_from_toml(value: TomlValue, witness: String, path: String, unknown_keys: UnknownKeys): Result<String, TomlError> {
    if (value is String(text)) {
        return Result<String, TomlError>.ok(text);
    }
    return Result<String, TomlError>.err(_toml_mismatch(path, "a string", value));
}

_from_toml(
    value: TomlValue, witness: TomlDateTime, path: String, unknown_keys: UnknownKeys
): Result<TomlDateTime, TomlError> {
    if (value is DateTime(when)) {
        return Result<TomlDateTime, TomlError>.ok(when);
    }
    return Result<TomlDateTime, TomlError>.err(_toml_mismatch(path, "a date-time", value));
}

_from_toml(value: TomlValue, witness: bool, path: String, unknown_keys: UnknownKeys): Result<bool, TomlError> {
    if (value is Boolean(flag)) {
        return Result<bool, TomlError>.ok(flag);
    }
    return Result<bool, TomlError>.err(_toml_mismatch(path, "a boolean", value));
}

_from_toml<T>(value: TomlValue, witness: T?, path: String, unknown_keys: UnknownKeys): Result<T?, TomlError> {
    var inner: T;
    var result = _from_toml(value, inner, path, unknown_keys);
    if (result.is_err()) {
        return Result<T?, TomlError>.err(result.error());
    }
    return Result<T?, TomlError>.ok(Optional<T>.Value(result.value()));
}

_from_toml<T>(
    value: TomlValue, witness: Array<T>, path: String, unknown_keys: UnknownKeys
): Result<Array<T>, TomlError> {
    var array = value.as_array();
    if (array.is_empty()) {
        return Result<Array<T>, TomlError>.err(_toml_mismatch(path, "an array", value));
    }
    var items = array.value();
    var out = Array<T>(items.count);
    var element: T;
    for (var index in 0..items.count) {
        var result = _from_toml(items[index], element, $"{path}[{index}]", unknown_keys);
        if (result.is_err()) {
            return Result<Array<T>, TomlError>.err(result.error());
        }
        out.append(result.value());
    }
    return Result<Array<T>, TomlError>.ok(out);
}

_from_toml<V>(
    value: TomlValue, witness: HashMap<String, V>, path: String, unknown_keys: UnknownKeys
): Result<HashMap<String, V>, TomlError> {
    var element: V;
    return _toml_read_members(value, HashMap<String, V>(), element, path, unknown_keys);
}

_from_toml<V>(
    value: TomlValue, witness: OrderedMap<String, V>, path: String, unknown_keys: UnknownKeys
): Result<OrderedMap<String, V>, TomlError> {
    var element: V;
    return _toml_read_members(value, OrderedMap<String, V>(), element, path, unknown_keys);
}

_from_toml<V>(
    value: TomlValue, witness: Map<String, V>, path: String, unknown_keys: UnknownKeys
): Result<Map<String, V>, TomlError> {
    var element: V;
    return _toml_read_members(value, Map<String, V>(), element, path, unknown_keys);
}

# Reads the members of table `value` into `map`, any map with `String`
# keys whose values are `V`s, like `element`.
_toml_read_members<TMap, V>(
    value: TomlValue, map: TMap, element: V, path: String, unknown_keys: UnknownKeys
): Result<TMap, TomlError> {
    var members = value.as_table();
    if (members.is_empty()) {
        return Result<TMap, TomlError>.err(_toml_mismatch(path, "a table", value));
    }
    for (var (key, member) in members.value()) {
        var result = _from_toml(member, element, _toml_path_key(path, key), unknown_keys);
        if (result.is_err()) {
            return Result<TMap, TomlError>.err(result.error());
        }
        map[key] = result.value();
    }
    return Result<TMap, TomlError>.ok(map);
}

_from_toml<T>(value: TomlValue, witness: T, path: String, unknown_keys: UnknownKeys): Result<T, TomlError> {
    var error = Optional<TomlError>.Empty;
    var out = witness;
    # Runtime locals of the second static block, which a `var` inside it
    # would make compile-time values.
    var known = Array<String>();
    var found = false;
    var failures = Array<TomlError>();
    static (value, path, unknown_keys, error, out) {
        if (reflect.is_same<T, i8>()) {
            error = _toml_integer(value, path, -128, 127, reflect.name<T>());
        } else if (reflect.is_same<T, i16>()) {
            error = _toml_integer(value, path, -32768, 32767, reflect.name<T>());
        } else if (reflect.is_same<T, i32>()) {
            error = _toml_integer(value, path, -2147483648, 2147483647, reflect.name<T>());
        } else if (reflect.is_same<T, i64>()) {
            error = _toml_integer(value, path, -9223372036854775807 - 1, 9223372036854775807, reflect.name<T>());
        } else if (reflect.is_same<T, u8>()) {
            error = _toml_integer(value, path, 0, 255, reflect.name<T>());
        } else if (reflect.is_same<T, u16>()) {
            error = _toml_integer(value, path, 0, 65535, reflect.name<T>());
        } else if (reflect.is_same<T, u32>()) {
            error = _toml_integer(value, path, 0, 4294967295, reflect.name<T>());
        } else if (reflect.is_same<T, u64>()) {
            error = _toml_integer(value, path, 0, 9223372036854775807, reflect.name<T>());
        } else if (reflect.is_same<T, float>() || reflect.is_same<T, double>()) {
            if (value.as_float().is_empty()) {
                error = Optional<TomlError>.Value(_toml_mismatch(path, "a number", value));
            }
        } else if (reflect.is_enum<T>()) {
            reflect.assert(
                !reflect.name<T>().starts_with("Result<"),
                $"'decode' cannot convert type '{reflect.name<T>()}' from TOML"
            );
            if (_toml_case_name(value).is_empty) {
                error = Optional<TomlError>.Value(_toml_mismatch(path, "a string or a table with one key", value));
            }
        } else if (reflect.is_struct<T>()) {
            if (value.as_table().is_empty()) {
                error = Optional<TomlError>.Value(_toml_mismatch(path, "a table", value));
            }
        } else {
            reflect.error($"'decode' cannot convert type '{reflect.name<T>()}' from TOML");
        }
    }
    if (error.is_value()) {
        return Result<T, TomlError>.err(error.value());
    }
    static (value, path, unknown_keys, error, out, known, found, failures) {
        if (reflect.is_same<T, i8>()
            || reflect.is_same<T, i16>()
            || reflect.is_same<T, i32>()
            || reflect.is_same<T, i64>()
            || reflect.is_same<T, u8>()
            || reflect.is_same<T, u16>()
            || reflect.is_same<T, u32>()
            || reflect.is_same<T, u64>()) {
            out = value.as_int().value() as T;
        } else if (reflect.is_same<T, float>() || reflect.is_same<T, double>()) {
            out = value.as_float().value() as T;
        } else if (reflect.is_enum<T>()) {
            var name = _toml_case_name(value);
            var payload = _toml_member(value, name);
            var case_path = _toml_path_key(path, name);
            for (var case in reflect.cases<T>()) {
                if (name == case.name) {
                    found = true;
                    if (case.values.is_empty) {
                        if (value.as_string().is_empty()) {
                            error = Optional<TomlError>.Value(
                                _toml_error(
                                    path,
                                    $"case '{case.name}' carries no values; write it as the string \"{case.name}\""
                                )
                            );
                        } else {
                            out = case.get();
                        }
                    } else if (value.as_string().is_value()) {
                        error = Optional<TomlError>.Value(
                            _toml_error(
                                path, $"case '{case.name}' carries values; write it as {{ {case.name} = {{ ... }} }}"
                            )
                        );
                    } else if (payload.as_table().is_empty()) {
                        error = Optional<TomlError>.Value(_toml_mismatch(case_path, "a table", payload));
                    } else {
                        # `case.get(...)` takes every value at once, so each
                        # count has its own call; a failed value records its
                        # error in `failures` and gives a default.
                        if (case.values.count == 1) {
                            var a = case.values[0];
                            out = case.get(
                                _toml_case_value<a.Type>(payload, a.name, case_path, unknown_keys, failures)
                            );
                        } else if (case.values.count == 2) {
                            var a = case.values[0];
                            var b = case.values[1];
                            out = case.get(
                                _toml_case_value<a.Type>(payload, a.name, case_path, unknown_keys, failures),
                                _toml_case_value<b.Type>(payload, b.name, case_path, unknown_keys, failures)
                            );
                        } else if (case.values.count == 3) {
                            var a = case.values[0];
                            var b = case.values[1];
                            var c = case.values[2];
                            out = case.get(
                                _toml_case_value<a.Type>(payload, a.name, case_path, unknown_keys, failures),
                                _toml_case_value<b.Type>(payload, b.name, case_path, unknown_keys, failures),
                                _toml_case_value<c.Type>(payload, c.name, case_path, unknown_keys, failures)
                            );
                        } else if (case.values.count == 4) {
                            var a = case.values[0];
                            var b = case.values[1];
                            var c = case.values[2];
                            var d = case.values[3];
                            out = case.get(
                                _toml_case_value<a.Type>(payload, a.name, case_path, unknown_keys, failures),
                                _toml_case_value<b.Type>(payload, b.name, case_path, unknown_keys, failures),
                                _toml_case_value<c.Type>(payload, c.name, case_path, unknown_keys, failures),
                                _toml_case_value<d.Type>(payload, d.name, case_path, unknown_keys, failures)
                            );
                        } else {
                            reflect.error(
                                $"'decode' cannot convert case '{case.name}' of '{reflect.name<T>()}': it carries more than 4 values"
                            );
                        }
                        for (var item in case.values) {
                            known.append(item.name);
                        }
                        if (failures.count > 0) {
                            error = Optional<TomlError>.Value(failures[0]);
                        } else if (unknown_keys == UnknownKeys.Reject) {
                            error = _toml_unknown_key(payload, known, case_path);
                        }
                    }
                }
            }
            if (!found) {
                error = Optional<TomlError>.Value(
                    _toml_error(path, $"'{name}' is not a case of '{reflect.name<T>()}'")
                );
            }
        } else if (reflect.is_struct<T>()) {
            out = _toml_new(out);
            for (var field in reflect.properties<T>()) {
                if (field.has_attribute<serialize.Ignore>()) {
                    continue;
                }
                # A shallow check, to name the property; the types
                # inside an array or a struct are checked when they
                # are converted.
                var convertible = !field.type_name.starts_with("Result<")
                    && (reflect.is_struct<field.Type>()
                        || reflect.is_enum<field.Type>()
                        || reflect.is_same<field.Type, bool>()
                        || reflect.is_same<field.Type, i8>()
                        || reflect.is_same<field.Type, i16>()
                        || reflect.is_same<field.Type, i32>()
                        || reflect.is_same<field.Type, i64>()
                        || reflect.is_same<field.Type, u8>()
                        || reflect.is_same<field.Type, u16>()
                        || reflect.is_same<field.Type, u32>()
                        || reflect.is_same<field.Type, u64>()
                        || reflect.is_same<field.Type, float>()
                        || reflect.is_same<field.Type, double>());
                reflect.assert(
                    convertible,
                    $"'decode' cannot convert property '{field.name}' of type '{field.type_name}' from TOML"
                );
                var key = field.name;
                if (field.has_attribute<serialize.Name>()) {
                    key = field.attribute<serialize.Name>().value;
                }
                known.append(key);
                if (error.is_empty()) {
                    if (value.contains(key)) {
                        var member = _from_toml(
                            _toml_member(value, key), field.get(out), _toml_path_key(path, key), unknown_keys
                        );
                        if (member.is_err()) {
                            error = Optional<TomlError>.Value(member.error());
                        } else {
                            field.set(out, member.value());
                        }
                    } else if (field.has_attribute<serialize.Required>()) {
                        error = Optional<TomlError>.Value(_toml_error(path, $"missing required key '{key}'"));
                    }
                }
            }
            if (error.is_empty() && unknown_keys == UnknownKeys.Reject) {
                error = _toml_unknown_key(value, known, path);
            }
        }
    }
    if (error.is_value()) {
        return Result<T, TomlError>.err(error.value());
    }
    return Result<T, TomlError>.ok(out);
}

# A new `T`, from its constructor that takes no arguments; `witness` only
# names the type.
_toml_new<T>(witness: T): T {
    return T();
}

# Empty when `value` is an integer in [low, high], else the error.
_toml_integer(value: TomlValue, path: String, low: long, high: long, type_name: String): TomlError? {
    var number = value.as_int();
    if (number.is_empty()) {
        return Optional<TomlError>.Value(_toml_mismatch(path, "an integer", value));
    }
    var n = number.value();
    if (n < low || n > high) {
        return Optional<TomlError>.Value(_toml_error(path, $"{n} does not fit in '{type_name}'"));
    }
    return Optional<TomlError>.Empty;
}

# The first key of table `value` that is not in `known`, as an error.
_toml_unknown_key(value: TomlValue, known: Array<String>, path: String): TomlError? {
    for (var (key, member) in value.as_table().value()) {
        if (!known.contains(key)) {
            return Optional<TomlError>.Value(_toml_error(_toml_path_key(path, key), $"unknown key '{key}'"));
        }
    }
    return Optional<TomlError>.Empty;
}

# The case `value` names: a string, or the one key of a table; empty for
# anything else.
_toml_case_name(value: TomlValue): String {
    if (value is String(text)) {
        return text;
    }
    var members = value.as_table();
    if (members.is_value() && members.value().count == 1) {
        for (var (key, member) in members.value()) {
            return key;
        }
    }
    return "";
}

# Value `key` of a case, read from `payload` as a `T`, or a default `T`
# when it or an earlier value failed, which goes in `failures`. A missing
# key reads as an empty `Optional`, and is an error for anything else.
_toml_case_value<T>(
    payload: TomlValue, key: String, path: String, unknown_keys: UnknownKeys, failures: Array<TomlError>
): T {
    var witness: T;
    if (failures.count > 0) {
        return witness;
    }
    if (!payload.contains(key)) {
        if (!_toml_is_optional(witness)) {
            failures.append(_toml_error(path, $"missing value '{key}'"));
        }
        return witness;
    }
    var result = _from_toml(_toml_member(payload, key), witness, _toml_path_key(path, key), unknown_keys);
    if (result.is_err()) {
        failures.append(result.error());
        return witness;
    }
    return result.value();
}

_toml_is_optional<T>(witness: T?): bool {
    return true;
}

_toml_is_optional<T>(witness: T): bool {
    return false;
}

# `value[key]`, as a call: an indexer in a static block's emitted code
# cannot choose its overload yet.
_toml_member(value: TomlValue, key: String): TomlValue {
    var found = value.try_get(key);
    if (found.is_value()) {
        return found.value();
    }
    return TomlValue.table();
}

_toml_error(path: String, message: String): TomlError {
    var error = TomlError($"{path}: {message}", line = 0, column = 0);
    error.value_path = path;
    return error;
}

_toml_mismatch(path: String, expected: String, found: TomlValue): TomlError {
    return _toml_error(path, $"expected {expected}, found {_toml_kind(found)}");
}
