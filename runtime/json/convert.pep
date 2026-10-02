## Struct conversion: `encode` and `decode` turn Pepper values into JSON text
## and back, through reflection, with no per-type code to write.

import serialize;
import "parse";
import "value";

## What `decode` does with an object key that names no property of the
## struct it is read into.
export enum UnknownKeys {
    ## Skips the key and its value.
    Ignore,
    ## Fails with an error naming the key and its path.
    Reject,
}

## Converts `value` to a `JsonValue`.
##
## `T` may be a number type, `bool`, `String`, an enum (a case that carries
## no values as its name, `"Point"`; one that carries values as
## `{"Circle": {"radius": 2}}`), `Optional<U>` (the value, or `null`), `Array<U>`, a map with `String` keys (`HashMap`, `OrderedMap` or
## `Map`) as an object, `JsonValue` itself, or a struct, whose public
## properties become an object's members in declaration order. Element and
## property types follow the same rules, so structs nest.
##
## A struct property takes its key from `[Name("key")]` when it has one,
## and is left out when marked `[Ignore]` (the attributes of the `serialize`
## module, which `json` exports). A property of a struct type that holds no
## object (a struct field never assigned) is written as `null`.
##
## The conversion is generated while compiling, by a `static` block per
## type. A type it cannot convert, such as a `Result` or an `io.File`, is a
## compile error naming the property:
## `'encode' cannot convert property 'outcome' of type 'Result<int>' to JSON`.
##
## @typeParam T the type of the value
## @param value the value to convert
## @returns the value as JSON
## @example
##     import json;
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
##         assert(json.to_json(p)["y"].as_int().value() == 2, "a member");
##         return 0;
##     }
export to_json<T>(value: T): JsonValue {
    return _to_json(value);
}

## Writes `value` as JSON text, converting it as `to_json` does.
##
## @typeParam T the type of the value
## @param value the value to write
## @param indent spaces per nesting level; 0, the default, writes compact
##   text on one line
## @param ascii_only whether to escape every character outside ASCII as
##   `\u`
## @returns the JSON text
## @example
##     import json;
##
##     struct ServerConfig {
##         var host: String;
##         var port: int;
##         [Name("max-connections")]
##         var max_connections: int;
##         [Ignore]
##         var started_at: long;
##     }
##
##     main(): int {
##         var config = ServerConfig();
##         config.host = "localhost";
##         config.port = 8080;
##         config.max_connections = 16;
##         var text = json.encode(config);
##         assert(text == "{\"host\":\"localhost\",\"port\":8080,\"max-connections\":16}", "compact");
##         return 0;
##     }
export encode<T>(value: T, indent: int = 0, ascii_only: bool = false): String {
    var root = _to_json(value);
    if (indent > 0) {
        return root.to_pretty_string(indent, ascii_only);
    }
    return root.to_string(ascii_only);
}

## Converts a `JsonValue` to a `T`, the reverse of `to_json`.
##
## A struct is made with its constructor that takes no arguments, then each
## property found in the object is read in. A missing key leaves its
## property at its default, unless the property is marked `[Required]`,
## which makes it an error; a property marked `[Ignore]` is never read. A
## key that names no property is skipped, or with
## `unknown_keys = UnknownKeys.Reject` is an error.
##
## A number converts to an integer type when it has no fraction and fits
## the type, and to `float` or `double` always. `null` converts only to an
## `Optional` (as none) and to `JsonValue`.
##
## An error names where in the document it is, as a path from the root `$`
## in its `value_path` and at the start of its message, and has no line or
## column, since there is no text: `$.server.port: expected a number, found
## a string`.
##
## @typeParam T the type to convert to
## @param value the JSON value
## @param unknown_keys what to do with an object key that names no property
## @returns the converted value, or the first error
## @example
##     import json;
##
##     struct Point {
##         var x: int;
##         var y: int;
##     }
##
##     main(): int {
##         var parsed = json.parse("{\"x\": 1, \"y\": 2}");
##         var p = json.from_json<Point>(parsed.value());
##         assert(p.value().y == 2, "a property");
##         return 0;
##     }
export from_json<T>(value: JsonValue, unknown_keys: UnknownKeys = UnknownKeys.Ignore): Result<T, JsonError> {
    var witness: T;
    return _from_json(value, witness, "$", unknown_keys);
}

## Parses JSON text and converts it to a `T`: `parse`, then `from_json`.
##
## @typeParam T the type to convert to
## @param text the JSON text
## @param unknown_keys what to do with an object key that names no property
## @param comments whether to accept JSONC: comments and trailing commas
## @param path the name of the text (a file name, say), which the error's
##   `to_string()` puts first
## @returns the value, or the first error: a syntax error, or a conversion
##   error with its path in the document; either has its line and column
## @example
##     import json;
##
##     struct ServerConfig {
##         var host: String;
##         [Required]
##         var port: int;
##         var tags: Array<String>;
##         var timeout: int?;
##     }
##
##     main(): int {
##         var config = json.decode<ServerConfig>("{\"host\": \"a\", \"port\": 80, \"tags\": [\"x\"]}");
##         assert(config.value().port == 80, "a number");
##         assert(config.value().tags[0] == "x", "an array");
##         assert(config.value().timeout.is_none(), "a missing optional");
##
##         var bad = json.decode<ServerConfig>("{\"port\": \"80\"}", path = "server.json");
##         assert(bad.error().to_string() == "server.json:1:10: error: $.port: expected a number, found a string", "a path");
##         return 0;
##     }
export decode<T>(
    text: String, unknown_keys: UnknownKeys = UnknownKeys.Ignore, comments: bool = false, path: String = ""
): Result<T, JsonError> {
    var parsed = parse(text, comments = comments, path = path);
    if (parsed.is_err()) {
        return Result<T, JsonError>.err(parsed.error());
    }
    var witness: T;
    var result = _from_json(parsed.value(), witness, "$", unknown_keys);
    if (result.is_err()) {
        var error = result.error();
        error.path = path;
        var offset = _json_locate(text, comments, error.value_path);
        if (offset.is_some()) {
            _json_place(error, text, offset.value());
        }
        return Result<T, JsonError>.err(error);
    }
    return result;
}

# ── Encoding ───────────────────────────────────────────────────────────────
#
# One overload per kind of type: overload resolution picks the most
# specialized, so `Array<T>` and `T?` take their own, and the catch-all
# `_to_json<T>` handles numbers, enums and structs in a static block.

_to_json(value: String): JsonValue {
    if (value === __null) {
        return JsonValue.Null;
    }
    return JsonValue.String(value);
}

_to_json(value: JsonValue): JsonValue {
    if (value === __null) {
        return JsonValue.Null;
    }
    return value;
}

_to_json(value: bool): JsonValue {
    return JsonValue.Bool(value);
}

_to_json<T>(value: T?): JsonValue {
    if (value.is_some()) {
        return _to_json(value.value());
    }
    return JsonValue.Null;
}

_to_json<T>(value: Array<T>): JsonValue {
    if (value === __null) {
        return JsonValue.Null;
    }
    var items = Array<JsonValue>(value.count);
    for (var element in value) {
        items.append(_to_json(element));
    }
    return JsonValue.Array(items);
}

_to_json<V>(value: HashMap<String, V>): JsonValue {
    return _json_object_of(value);
}

_to_json<V>(value: OrderedMap<String, V>): JsonValue {
    return _json_object_of(value);
}

_to_json<V>(value: Map<String, V>): JsonValue {
    return _json_object_of(value);
}

# An object of the members of `map`, any map with `String` keys.
_json_object_of<TMap>(map: TMap): JsonValue {
    if (map === __null) {
        return JsonValue.Null;
    }
    var members = OrderedMap<String, JsonValue>();
    for (var (key, member) in map) {
        members[key] = _to_json(member);
    }
    return JsonValue.Object(members);
}

_to_json<T>(value: T): JsonValue {
    var out = JsonValue.Null;
    var present = true;
    static (out, value, present) {
        if (reflect.is_same<T, i8>()
            || reflect.is_same<T, i16>()
            || reflect.is_same<T, i32>()
            || reflect.is_same<T, i64>()
            || reflect.is_same<T, u8>()
            || reflect.is_same<T, u16>()
            || reflect.is_same<T, u32>()) {
            out = JsonValue.Integer(value as long);
        } else if (reflect.is_same<T, u64>()) {
            out = _ulong_to_json(value);
        } else if (reflect.is_same<T, float>() || reflect.is_same<T, double>()) {
            out = JsonValue.Number(value as double);
        } else if (reflect.is_enum<T>()) {
            reflect.assert(
                !reflect.name<T>().starts_with("Result<"), $"'encode' cannot convert type '{reflect.name<T>()}' to JSON"
            );
            # A case that carries nothing is its name; one that carries
            # values is `{"Case": {"value": ...}}`. A reference enum's slot
            # may hold no value, written as `null`.
            if (reflect.is_reference<T>()) {
                present = !_json_object_or_null(value).is_null();
            }
            for (var case in reflect.cases<T>()) {
                if (present && case.matches(value)) {
                    if (case.values.is_empty) {
                        out = JsonValue.String(case.name);
                    } else {
                        out = _json_case_object(case.name);
                        for (var item in case.values) {
                            _json_put(_json_member(out, case.name), item.name, _to_json(item.get(value)));
                        }
                    }
                }
            }
        } else if (reflect.is_struct<T>()) {
            out = _json_object_or_null(value);
            for (var field in reflect.properties<T>()) {
                if (!field.has_attribute<serialize.Ignore>()) {
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
                        $"'encode' cannot convert property '{field.name}' of type '{field.type_name}' to JSON"
                    );
                    var key = field.name;
                    if (field.has_attribute<serialize.Name>()) {
                        key = field.attribute<serialize.Name>().value;
                    }
                    _json_put(out, key, _to_json(field.get(value)));
                }
            }
        } else {
            reflect.error($"'encode' cannot convert type '{reflect.name<T>()}' to JSON");
        }
    }
    return out;
}

_ulong_to_json(value: ulong): JsonValue {
    if (value <= 9223372036854775807) {
        return JsonValue.Integer(value as long);
    }
    return JsonValue.Number(value as double);
}

# An empty object for a struct value, or `Null` for a struct reference that
# holds none.
_json_object_or_null<T>(value: T): JsonValue {
    if (value === __null) {
        return JsonValue.Null;
    }
    return JsonValue.object();
}

# ── Decoding ───────────────────────────────────────────────────────────────
#
# As for encoding, one overload per kind of type, picked by the type of
# `witness`: a value of the target type whose only use is choosing the
# overload (a struct's current property, or a default-initialized local).

_from_json(
    value: JsonValue, witness: JsonValue, path: String, unknown_keys: UnknownKeys
): Result<JsonValue, JsonError> {
    return Result<JsonValue, JsonError>.ok(value);
}

_from_json(value: JsonValue, witness: String, path: String, unknown_keys: UnknownKeys): Result<String, JsonError> {
    if (value is String(text)) {
        return Result<String, JsonError>.ok(text);
    }
    if (value is Null) {
        return Result<String, JsonError>.ok(__null);
    }
    return Result<String, JsonError>.err(_json_mismatch(path, "a string", value));
}

_from_json(value: JsonValue, witness: bool, path: String, unknown_keys: UnknownKeys): Result<bool, JsonError> {
    if (value is Bool(flag)) {
        return Result<bool, JsonError>.ok(flag);
    }
    return Result<bool, JsonError>.err(_json_mismatch(path, "a boolean", value));
}

_from_json<T>(value: JsonValue, witness: T?, path: String, unknown_keys: UnknownKeys): Result<T?, JsonError> {
    if (value is Null) {
        return Result<T?, JsonError>.ok(Optional<T>.none());
    }
    var inner: T;
    var result = _from_json(value, inner, path, unknown_keys);
    if (result.is_err()) {
        return Result<T?, JsonError>.err(result.error());
    }
    return Result<T?, JsonError>.ok(Optional<T>.some(result.value()));
}

_from_json<T>(
    value: JsonValue, witness: Array<T>, path: String, unknown_keys: UnknownKeys
): Result<Array<T>, JsonError> {
    if (value is Null) {
        return Result<Array<T>, JsonError>.ok(__null);
    }
    var array = value.as_array();
    if (array.is_none()) {
        return Result<Array<T>, JsonError>.err(_json_mismatch(path, "an array", value));
    }
    var items = array.value();
    var out = Array<T>(items.count);
    var element: T;
    for (var index in 0..items.count) {
        var result = _from_json(items[index], element, $"{path}[{index}]", unknown_keys);
        if (result.is_err()) {
            return Result<Array<T>, JsonError>.err(result.error());
        }
        out.append(result.value());
    }
    return Result<Array<T>, JsonError>.ok(out);
}

_from_json<V>(
    value: JsonValue, witness: HashMap<String, V>, path: String, unknown_keys: UnknownKeys
): Result<HashMap<String, V>, JsonError> {
    if (value is Null) {
        return Result<HashMap<String, V>, JsonError>.ok(__null);
    }
    var element: V;
    return _json_read_members(value, HashMap<String, V>(), element, path, unknown_keys);
}

_from_json<V>(
    value: JsonValue, witness: OrderedMap<String, V>, path: String, unknown_keys: UnknownKeys
): Result<OrderedMap<String, V>, JsonError> {
    if (value is Null) {
        return Result<OrderedMap<String, V>, JsonError>.ok(__null);
    }
    var element: V;
    return _json_read_members(value, OrderedMap<String, V>(), element, path, unknown_keys);
}

_from_json<V>(
    value: JsonValue, witness: Map<String, V>, path: String, unknown_keys: UnknownKeys
): Result<Map<String, V>, JsonError> {
    if (value is Null) {
        return Result<Map<String, V>, JsonError>.ok(__null);
    }
    var element: V;
    return _json_read_members(value, Map<String, V>(), element, path, unknown_keys);
}

# Reads the members of object `value` into `map`, any map with `String`
# keys whose values are `V`s, like `element`.
_json_read_members<TMap, V>(
    value: JsonValue, map: TMap, element: V, path: String, unknown_keys: UnknownKeys
): Result<TMap, JsonError> {
    var members = value.as_object();
    if (members.is_none()) {
        return Result<TMap, JsonError>.err(_json_mismatch(path, "an object", value));
    }
    for (var (key, member) in members.value()) {
        var result = _from_json(member, element, _json_path_key(path, key), unknown_keys);
        if (result.is_err()) {
            return Result<TMap, JsonError>.err(result.error());
        }
        map[key] = result.value();
    }
    return Result<TMap, JsonError>.ok(map);
}

_from_json<T>(value: JsonValue, witness: T, path: String, unknown_keys: UnknownKeys): Result<T, JsonError> {
    var error = Optional<JsonError>.none();
    var out = witness;
    # Runtime locals of the second static block, which a `var` inside it
    # would make compile-time values.
    var known = Array<String>();
    var found = false;
    var failures = Array<JsonError>();
    static (value, path, unknown_keys, error, out) {
        if (reflect.is_same<T, i8>()) {
            error = _json_integer(value, path, -128, 127, reflect.name<T>());
        } else if (reflect.is_same<T, i16>()) {
            error = _json_integer(value, path, -32768, 32767, reflect.name<T>());
        } else if (reflect.is_same<T, i32>()) {
            error = _json_integer(value, path, -2147483648, 2147483647, reflect.name<T>());
        } else if (reflect.is_same<T, i64>()) {
            error = _json_integer(value, path, -9223372036854775807 - 1, 9223372036854775807, reflect.name<T>());
        } else if (reflect.is_same<T, u8>()) {
            error = _json_integer(value, path, 0, 255, reflect.name<T>());
        } else if (reflect.is_same<T, u16>()) {
            error = _json_integer(value, path, 0, 65535, reflect.name<T>());
        } else if (reflect.is_same<T, u32>()) {
            error = _json_integer(value, path, 0, 4294967295, reflect.name<T>());
        } else if (reflect.is_same<T, u64>()) {
            error = _json_integer(value, path, 0, 9223372036854775807, reflect.name<T>());
        } else if (reflect.is_same<T, float>() || reflect.is_same<T, double>()) {
            if (value.as_double().is_none()) {
                error = Optional<JsonError>.some(_json_mismatch(path, "a number", value));
            }
        } else if (reflect.is_enum<T>()) {
            reflect.assert(
                !reflect.name<T>().starts_with("Result<"),
                $"'decode' cannot convert type '{reflect.name<T>()}' from JSON"
            );
            if (_json_case_name(value).is_empty && !(reflect.is_reference<T>() && value.is_null())) {
                error = Optional<JsonError>.some(_json_mismatch(path, "a string or an object with one key", value));
            }
        } else if (reflect.is_struct<T>()) {
            if (value.as_object().is_none() && !value.is_null()) {
                error = Optional<JsonError>.some(_json_mismatch(path, "an object", value));
            }
        } else {
            reflect.error($"'decode' cannot convert type '{reflect.name<T>()}' from JSON");
        }
    }
    if (error.is_some()) {
        return Result<T, JsonError>.err(error.value());
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
            out = value.as_double().value() as T;
        } else if (reflect.is_enum<T>()) {
            if (reflect.is_reference<T>()) {
                if (value.is_null()) {
                    out = _json_null(out);
                    found = true;
                }
            }
            var name = _json_case_name(value);
            var payload = _json_member(value, name);
            var case_path = _json_path_key(path, name);
            for (var case in reflect.cases<T>()) {
                if (name == case.name) {
                    found = true;
                    if (case.values.is_empty) {
                        if (value.as_string().is_none()) {
                            error = Optional<JsonError>.some(
                                _json_error(
                                    path,
                                    $"case '{case.name}' carries no values; write it as the string \"{case.name}\""
                                )
                            );
                        } else {
                            out = case.get();
                        }
                    } else if (value.as_string().is_some()) {
                        error = Optional<JsonError>.some(
                            _json_error(
                                path, $"case '{case.name}' carries values; write it as {{\"{case.name}\": {{...}}}}"
                            )
                        );
                    } else if (payload.as_object().is_none()) {
                        error = Optional<JsonError>.some(_json_mismatch(case_path, "an object", payload));
                    } else {
                        # `case.get(...)` takes every value at once, so each
                        # count has its own call; a failed value records its
                        # error in `failures` and gives a default.
                        if (case.values.count == 1) {
                            var a = case.values[0];
                            out = case.get(
                                _json_case_value < a.Type > (payload, a.name, case_path, unknown_keys, failures)
                            );
                        } else if (case.values.count == 2) {
                            var a = case.values[0];
                            var b = case.values[1];
                            out = case.get(
                                _json_case_value < a.Type > (payload, a.name, case_path, unknown_keys, failures),
                                _json_case_value < b.Type > (payload, b.name, case_path, unknown_keys, failures)
                            );
                        } else if (case.values.count == 3) {
                            var a = case.values[0];
                            var b = case.values[1];
                            var c = case.values[2];
                            out = case.get(
                                _json_case_value < a.Type > (payload, a.name, case_path, unknown_keys, failures),
                                _json_case_value < b.Type > (payload, b.name, case_path, unknown_keys, failures),
                                _json_case_value < c.Type > (payload, c.name, case_path, unknown_keys, failures)
                            );
                        } else if (case.values.count == 4) {
                            var a = case.values[0];
                            var b = case.values[1];
                            var c = case.values[2];
                            var d = case.values[3];
                            out = case.get(
                                _json_case_value < a.Type > (payload, a.name, case_path, unknown_keys, failures),
                                _json_case_value < b.Type > (payload, b.name, case_path, unknown_keys, failures),
                                _json_case_value < c.Type > (payload, c.name, case_path, unknown_keys, failures),
                                _json_case_value < d.Type > (payload, d.name, case_path, unknown_keys, failures)
                            );
                        } else if (case.values.count == 5) {
                            var a = case.values[0];
                            var b = case.values[1];
                            var c = case.values[2];
                            var d = case.values[3];
                            var e = case.values[4];
                            out = case.get(
                                _json_case_value < a.Type > (payload, a.name, case_path, unknown_keys, failures),
                                _json_case_value < b.Type > (payload, b.name, case_path, unknown_keys, failures),
                                _json_case_value < c.Type > (payload, c.name, case_path, unknown_keys, failures),
                                _json_case_value < d.Type > (payload, d.name, case_path, unknown_keys, failures),
                                _json_case_value < e.Type > (payload, e.name, case_path, unknown_keys, failures)
                            );
                        } else if (case.values.count == 6) {
                            var a = case.values[0];
                            var b = case.values[1];
                            var c = case.values[2];
                            var d = case.values[3];
                            var e = case.values[4];
                            var f = case.values[5];
                            out = case.get(
                                _json_case_value < a.Type > (payload, a.name, case_path, unknown_keys, failures),
                                _json_case_value < b.Type > (payload, b.name, case_path, unknown_keys, failures),
                                _json_case_value < c.Type > (payload, c.name, case_path, unknown_keys, failures),
                                _json_case_value < d.Type > (payload, d.name, case_path, unknown_keys, failures),
                                _json_case_value < e.Type > (payload, e.name, case_path, unknown_keys, failures),
                                _json_case_value < f.Type > (payload, f.name, case_path, unknown_keys, failures)
                            );
                        } else {
                            reflect.error(
                                $"'decode' cannot convert case '{case.name}' of '{reflect.name<T>()}': it carries more than 6 values"
                            );
                        }
                        for (var item in case.values) {
                            known.append(item.name);
                        }
                        if (failures.count > 0) {
                            error = Optional<JsonError>.some(failures[0]);
                        } else if (unknown_keys == UnknownKeys.Reject) {
                            error = _json_unknown_key(payload, known, case_path);
                        }
                    }
                }
            }
            if (!found) {
                error = Optional<JsonError>.some(_json_error(path, $"'{name}' is not a case of '{reflect.name<T>()}'"));
            }
        } else if (reflect.is_struct<T>()) {
            out = _json_new(out, value.is_null());
            for (var field in reflect.properties<T>()) {
                if (!field.has_attribute<serialize.Ignore>()) {
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
                        $"'decode' cannot convert property '{field.name}' of type '{field.type_name}' from JSON"
                    );
                    var key = field.name;
                    if (field.has_attribute<serialize.Name>()) {
                        key = field.attribute<serialize.Name>().value;
                    }
                    known.append(key);
                    if (error.is_none() && !value.is_null()) {
                        if (value.contains(key)) {
                            var member = _from_json(
                                _json_member(value, key), field.get(out), _json_path_key(path, key), unknown_keys
                            );
                            if (member.is_err()) {
                                error = Optional<JsonError>.some(member.error());
                            } else {
                                field.set(out, member.value());
                            }
                        } else if (field.has_attribute<serialize.Required>()) {
                            error = Optional<JsonError>.some(_json_error(path, $"missing required key '{key}'"));
                        }
                    }
                }
            }
            if (error.is_none() && !value.is_null() && unknown_keys == UnknownKeys.Reject) {
                error = _json_unknown_key(value, known, path);
            }
        }
    }
    if (error.is_some()) {
        return Result<T, JsonError>.err(error.value());
    }
    return Result<T, JsonError>.ok(out);
}

# A new `T`, from its constructor that takes no arguments, or a null
# reference for JSON's `null`; `witness` only names the type.
_json_new<T>(witness: T, is_null: bool): T {
    if (is_null) {
        return __null;
    }
    return T();
}

# A null reference of `witness`'s type, for JSON's `null`.
_json_null<T>(witness: T): T {
    return __null;
}

# Empty when `value` is an integer in [low, high], else the error.
_json_integer(value: JsonValue, path: String, low: long, high: long, type_name: String): JsonError? {
    var number = value.as_int();
    if (number.is_none()) {
        if (value.as_double().is_some()) {
            return Optional<JsonError>.some(_json_error(path, $"expected an integer, found {value.to_string()}"));
        }
        return Optional<JsonError>.some(_json_mismatch(path, "a number", value));
    }
    var n = number.value();
    if (n < low || n > high) {
        return Optional<JsonError>.some(_json_error(path, $"{n} does not fit in '{type_name}'"));
    }
    return Optional<JsonError>.none();
}

# The first key of object `value` that is not in `known`, as an error.
_json_unknown_key(value: JsonValue, known: Array<String>, path: String): JsonError? {
    for (var (key, member) in value.as_object().value()) {
        if (!known.contains(key)) {
            return Optional<JsonError>.some(_json_error(_json_path_key(path, key), $"unknown key '{key}'"));
        }
    }
    return Optional<JsonError>.none();
}

# `{"name": {}}`, the form of a case that carries values.
_json_case_object(name: String): JsonValue {
    var object = JsonValue.object();
    object[name] = JsonValue.object();
    return object;
}

# The case `value` names: a string, or the one key of an object; empty for
# anything else.
_json_case_name(value: JsonValue): String {
    if (value is String(text)) {
        return text;
    }
    var members = value.as_object();
    if (members.is_some() && members.value().count == 1) {
        for (var (key, member) in members.value()) {
            return key;
        }
    }
    return "";
}

# Value `key` of a case, read from `payload` as a `T`, or a default `T`
# when it or an earlier value failed, which goes in `failures`. A missing
# key reads as `null`.
_json_case_value<T>(
    payload: JsonValue, key: String, path: String, unknown_keys: UnknownKeys, failures: Array<JsonError>
): T {
    var witness: T;
    if (failures.count > 0) {
        return witness;
    }
    var result = _from_json(_json_member(payload, key), witness, _json_path_key(path, key), unknown_keys);
    if (result.is_err()) {
        if (payload.contains(key)) {
            failures.append(result.error());
        } else {
            failures.append(_json_error(path, $"missing value '{key}'"));
        }
        return witness;
    }
    return result.value();
}

# Sets member `key` of `object`, when it is an object (a struct reference
# that holds none was written as `Null`).
_json_put(object: JsonValue, key: String, member: JsonValue) {
    if (object is Object(members)) {
        members[key] = member;
    }
}

# `value[key]`, as a call: an indexer in a static block's emitted code
# cannot choose its overload yet.
_json_member(value: JsonValue, key: String): JsonValue {
    return value[key];
}

_json_error(path: String, message: String): JsonError {
    var error = JsonError($"{path}: {message}", line = 0, column = 0);
    error.value_path = path;
    return error;
}

_json_mismatch(path: String, expected: String, found: JsonValue): JsonError {
    return _json_error(path, $"expected {expected}, found {_json_kind(found)}");
}

# How an error names a value's kind: "a string", "null".
_json_kind(value: JsonValue): String {
    match (value) {
        Null => { return "null"; }
        Bool(flag) => { return "a boolean"; }
        Integer(n) => { return "a number"; }
        Number(n) => { return "a number"; }
        String(text) => { return "a string"; }
        Array(items) => { return "an array"; }
        Object(members) => { return "an object"; }
    }
    return "";
}
