## `TomlValue`: a TOML value of any kind, and `TomlDateTime`, TOML's dates
## and times.

import "parse";
import "write";

## A TOML date, time, or date and time: an offset date-time
## (`1979-05-27T07:32:00Z`), a local date-time (`1979-05-27T07:32:00`), a
## local date (`1979-05-27`) or a local time (`07:32:00.5`).
##
## `has_date`, `has_time` and `has_offset` say which of the four it is;
## the fields of a part it does not have are 0. `to_string()` writes it in
## the RFC 3339 form TOML uses, with as many fraction digits as it was
## read with.
##
## @example
##     import toml;
##
##     var when = toml.TomlDateTime.offset(1979, 5, 27, 7, 32, 0, -420);
##     assert(when.to_string() == "1979-05-27T07:32:00-07:00", "an offset");
##     assert(toml.TomlDateTime.date(2024, 2, 29).to_string() == "2024-02-29", "a date");
export struct TomlDateTime {
    ## The year, 0 to 9999; 0 without a date.
    var year: int;
    ## The month, 1 to 12; 0 without a date.
    var month: int;
    ## The day of the month, from 1; 0 without a date.
    var day: int;
    ## The hour, 0 to 23.
    var hour: int;
    ## The minute, 0 to 59.
    var minute: int;
    ## The second, 0 to 59.
    var second: int;
    ## The fraction of the second, in nanoseconds.
    var nanosecond: int;
    ## How many digits of the fraction `to_string()` writes, 0 to 9; 0
    ## writes none.
    var fraction_digits: int;
    ## The offset from UTC in minutes (`-07:00` is -420); 0 for `Z`.
    var offset_minutes: int;
    ## Whether it has a date.
    var has_date: bool;
    ## Whether it has a time of day.
    var has_time: bool;
    ## Whether it has an offset from UTC, which only a date and time has.
    var has_offset: bool;

    ## Creates a local date-time at midnight on 0000-00-00, to fill in.
    construct() {
        has_date = true;
        has_time = true;
    }

    ## Returns a local date, such as `1979-05-27`.
    ##
    ## @param year the year
    ## @param month the month, from 1
    ## @param day the day of the month, from 1
    ## @returns the date
    static date(year: int, month: int, day: int): TomlDateTime {
        var value = TomlDateTime();
        value.year = year;
        value.month = month;
        value.day = day;
        value.has_time = false;
        return value;
    }

    ## Returns a local time of day, such as `07:32:00`.
    ##
    ## @param hour the hour
    ## @param minute the minute
    ## @param second the second
    ## @param nanosecond the fraction of the second, in nanoseconds; written
    ##   with as few digits as it needs
    ## @returns the time
    static time(hour: int, minute: int, second: int, nanosecond: int = 0): TomlDateTime {
        var value = TomlDateTime();
        value.has_date = false;
        value._set_time(hour, minute, second, nanosecond);
        return value;
    }

    ## Returns a local date-time, with no offset: `1979-05-27T07:32:00`.
    ##
    ## @param year the year
    ## @param month the month, from 1
    ## @param day the day of the month, from 1
    ## @param hour the hour
    ## @param minute the minute
    ## @param second the second
    ## @param nanosecond the fraction of the second, in nanoseconds
    ## @returns the date-time
    static local(
        year: int, month: int, day: int, hour: int, minute: int, second: int, nanosecond: int = 0
    ): TomlDateTime {
        var value = TomlDateTime.date(year, month, day);
        value.has_time = true;
        value._set_time(hour, minute, second, nanosecond);
        return value;
    }

    ## Returns a date-time at an offset from UTC: `1979-05-27T07:32:00Z`.
    ##
    ## @param year the year
    ## @param month the month, from 1
    ## @param day the day of the month, from 1
    ## @param hour the hour
    ## @param minute the minute
    ## @param second the second
    ## @param offset_minutes the offset from UTC in minutes; 0 is written
    ##   `Z`
    ## @param nanosecond the fraction of the second, in nanoseconds
    ## @returns the date-time
    static offset(
        year: int, month: int, day: int, hour: int, minute: int, second: int, offset_minutes: int, nanosecond: int = 0
    ): TomlDateTime {
        var value = TomlDateTime.local(year, month, day, hour, minute, second, nanosecond);
        value.has_offset = true;
        value.offset_minutes = offset_minutes;
        return value;
    }

    _set_time(hour: int, minute: int, second: int, nanosecond: int) {
        this.hour = hour;
        this.minute = minute;
        this.second = second;
        this.nanosecond = nanosecond;
        fraction_digits = 0;
        if (nanosecond > 0) {
            fraction_digits = 9;
            var rest = nanosecond;
            while (rest % 10 == 0) {
                rest = rest / 10;
                fraction_digits = fraction_digits - 1;
            }
        }
    }

    ## Returns the value as TOML writes it: `1979-05-27T07:32:00.5-07:00`,
    ## `1979-05-27`, `07:32:00`.
    ##
    ## @returns the text
    to_string(): String {
        var out = StringBuilder();
        if (has_date) {
            out.append($"{year:04}-{month:02}-{day:02}");
            if (has_time) {
                out.append("T");
            }
        }
        if (has_time) {
            out.append($"{hour:02}:{minute:02}:{second:02}");
            if (fraction_digits > 0) {
                var digits = $"{nanosecond:09}";
                out.append(".");
                out.append(digits.substr_bytes(0, fraction_digits as ulong));
            }
            if (has_offset) {
                if (offset_minutes == 0) {
                    out.append("Z");
                } else {
                    var minutes = offset_minutes < 0 ? -offset_minutes : offset_minutes;
                    out.append(offset_minutes < 0 ? "-" : "+");
                    out.append($"{minutes / 60:02}:{minutes % 60:02}");
                }
            }
        }
        return out.to_string();
    }
}

## A TOML value: a string, an integer, a float, a boolean, a date-time, an
## array or a table. `toml.parse` makes a table from a document, and
## `to_document` writes one back.
##
## Look members up with `value["key"]` and elements with `value[index]`,
## which panic when there is none; `try_get` and `lookup` give none
## instead, and `lookup` follows a dotted key (`"package.name"`). Then read
## the value with an `as_` method, which gives none when the value is of
## another kind, or `match` on its case.
##
## A `Table` keeps its keys in the order they were written. An `Array` or
## `Table` case holds its array or map by reference, so changing them
## through `value[key] = ...` or `append` changes every holder of the
## value.
##
## @example
##     import toml;
##
##     var package = toml.TomlValue.table();
##     package["name"] = toml.TomlValue.String("demo");
##     package["authors"] = toml.TomlValue.array([toml.TomlValue.String("Ada")]);
##     assert(package.to_string() == "{ name = \"demo\", authors = [\"Ada\"] }", "inline");
##     assert(package["name"].as_string().value() == "demo", "a lookup");
export enum TomlValue {
    ## A string.
    ##
    ## @param value the text
    String(value: String),
    ## A 64-bit integer.
    ##
    ## @param value the integer
    Integer(value: long),
    ## A 64-bit float, including `inf` and `nan`.
    ##
    ## @param value the number
    Float(value: double),
    ## `true` or `false`.
    ##
    ## @param value the boolean
    Boolean(value: bool),
    ## A date, a time, or both.
    ##
    ## @param value the date-time
    DateTime(value: TomlDateTime),
    ## An array, holding its elements in order.
    ##
    ## @param items the elements
    Array(items: Array<TomlValue>),
    ## A table, holding its members in the order they were written.
    ##
    ## @param members the members, by key
    Table(members: OrderedMap<String, TomlValue>),

    ## Returns a new, empty table.
    ##
    ## @returns a `Table` with no members
    static table(): TomlValue {
        return TomlValue.Table(OrderedMap<String, TomlValue>());
    }

    ## Returns an array holding `items`, which it keeps by reference rather
    ## than copying.
    ##
    ## @param items the elements; an empty array when not given
    ## @returns an `Array` of `items`
    static array(items: Array<TomlValue> = Array<TomlValue>()): TomlValue {
        return TomlValue.Array(items);
    }

    ## Reads `value[key]`: the member named `key` of a table.
    ##
    ## @param key the member's key
    ## @returns the member
    ## @panics if this is not a table or has no member named `key` ("no
    ##   key 'k' in the TOML table"); use `try_get` to check
    [](key: String): TomlValue {
        var found = try_get(key);
        if (found.is_empty()) {
            panic($"no key '{key}' in the TOML {type_name()}");
        }
        return found.value();
    }

    ## Writes `value[key] = member`: sets the member named `key` of a
    ## table. A new key goes at the end; an existing key keeps its place.
    ##
    ## @param key the member's key
    ## @param member the value to store
    ## @returns `member`, the value of the assignment expression
    ## @panics if this is not a table ("TomlValue[key] = value needs a
    ##   table")
    [](key: String, member: TomlValue): TomlValue {
        if (this is Table(members)) {
            members[key] = member;
            return member;
        }
        panic($"TomlValue[key] = value needs a table, not {_toml_kind(this)}");
        return member;
    }

    ## Reads `value[index]`: an element of an array.
    ##
    ## @param index the element's position, from 0
    ## @returns the element
    ## @panics if this is not an array ("TomlValue[index] needs an array")
    ## @panics if `index` is not less than the array's count (as `Array`'s
    ##   indexer does)
    [](index: ulong): TomlValue {
        if (this is Array(items)) {
            return items[index];
        }
        panic($"TomlValue[index] needs an array, not {_toml_kind(this)}");
        return this;
    }

    ## Writes `value[index] = element`: replaces an element of an array.
    ##
    ## @param index the element's position, from 0
    ## @param element the value to store
    ## @returns `element`, the value of the assignment expression
    ## @panics if this is not an array ("TomlValue[index] = value needs an
    ##   array")
    ## @panics if `index` is not less than the array's count
    [](index: ulong, element: TomlValue): TomlValue {
        if (this is Array(items)) {
            items[index] = element;
            return element;
        }
        panic($"TomlValue[index] = value needs an array, not {_toml_kind(this)}");
        return element;
    }

    ## Returns the member named `key`, when this is a table that has one.
    ##
    ## @param key the member's key
    ## @returns the member, or none
    try_get(key: String): TomlValue? {
        if (this is Table(members)) {
            return members.try_get(key);
        }
        return Optional<TomlValue>.Empty;
    }

    ## Returns the value at a dotted key below this table, read as TOML
    ## reads a key: `package.name`, `dependencies."my.crate".version`.
    ##
    ## @param key the dotted key
    ## @returns the value, or none when a part is missing, is not a table,
    ##   or `key` is not a valid TOML key
    ## @example
    ##     import toml;
    ##
    ##     var root = toml.parse("[package]\nname = \"demo\"").value();
    ##     assert(root.lookup("package.name").value().as_string().value() == "demo", "found");
    ##     assert(root.lookup("package.version").is_empty(), "missing");
    lookup(key: String): TomlValue? {
        var keys = _toml_split_key(key);
        if (keys.is_empty()) {
            return Optional<TomlValue>.Empty;
        }
        return get_path(keys.value());
    }

    ## Returns the value at the path of keys `keys` below this table.
    ##
    ## @param keys the keys, outermost first; empty gives this value
    ## @returns the value, or none when a part is missing or is not a table
    get_path(keys: Array<String>): TomlValue? {
        var here = this;
        for (var key in keys) {
            var next = here.try_get(key);
            if (next.is_empty()) {
                return next;
            }
            here = next.value();
        }
        return Optional<TomlValue>.Value(here);
    }

    ## Appends `element` to the end of an array.
    ##
    ## @param element the value to append
    ## @panics if this is not an array ("TomlValue.append needs an array")
    append(element: TomlValue) {
        if (this is Array(items)) {
            items.append(element);
            return;
        }
        panic($"TomlValue.append needs an array, not {_toml_kind(this)}");
    }

    ## Returns whether this is a table with a member named `key`.
    ##
    ## @param key the key to look for
    ## @returns true when the member exists
    contains(key: String): bool {
        if (this is Table(members)) {
            return members.contains(key);
        }
        return false;
    }

    ## Removes the member named `key` from a table.
    ##
    ## @param key the key to remove
    ## @returns true when this is a table and the member was there
    remove(key: String): bool {
        if (this is Table(members)) {
            return members.remove(key);
        }
        return false;
    }

    ## Returns what kind of value this is, as errors name it: `string`,
    ## `integer`, `float`, `boolean`, `date-time`, `array` or `table`.
    ##
    ## @returns the kind's name
    type_name(): String {
        match (this) {
            String(value) => { return "string"; }
            Integer(value) => { return "integer"; }
            Float(value) => { return "float"; }
            Boolean(value) => { return "boolean"; }
            DateTime(value) => { return "date-time"; }
            Array(items) => { return "array"; }
            Table(members) => { return "table"; }
        }
        return "";
    }

    ## Returns the string, when this is one.
    ##
    ## @returns the text of a `String`, or none
    as_string(): String? {
        if (this is String(value)) {
            return Optional<String>.Value(value);
        }
        return Optional<String>.Empty;
    }

    ## Returns the integer, when this is one.
    ##
    ## @returns the value of an `Integer`, or none
    as_int(): long? {
        if (this is Integer(value)) {
            return Optional<long>.Value(value);
        }
        return Optional<long>.Empty;
    }

    ## Returns the number as a `double`, when this is a `Float` or an
    ## `Integer`.
    ##
    ## @returns the number, or none
    as_float(): double? {
        match (this) {
            Integer(value) => { return Optional<double>.Value(value as double); }
            Float(value) => { return Optional<double>.Value(value); }
            else => {}
        }
        return Optional<double>.Empty;
    }

    ## Returns the boolean, when this is one.
    ##
    ## @returns the value of a `Boolean`, or none
    as_bool(): bool? {
        if (this is Boolean(value)) {
            return Optional<bool>.Value(value);
        }
        return Optional<bool>.Empty;
    }

    ## Returns the date-time, when this is one.
    ##
    ## @returns the value of a `DateTime`, or none
    as_date_time(): TomlDateTime? {
        if (this is DateTime(value)) {
            return Optional<TomlDateTime>.Value(value);
        }
        return Optional<TomlDateTime>.Empty;
    }

    ## Returns the elements, when this is an array. The array is the one
    ## this value holds, not a copy.
    ##
    ## @returns the elements of an `Array`, or none
    as_array(): Array<TomlValue>? {
        if (this is Array(items)) {
            return Optional<Array<TomlValue>>.Value(items);
        }
        return Optional<Array<TomlValue>>.Empty;
    }

    ## Returns the members, when this is a table. The map is the one this
    ## value holds, not a copy.
    ##
    ## @returns the members of a `Table`, or none
    as_table(): OrderedMap<String, TomlValue>? {
        if (this is Table(members)) {
            return Optional<OrderedMap<String, TomlValue>>.Value(members);
        }
        return Optional<OrderedMap<String, TomlValue>>.Empty;
    }

    ## Returns the value as TOML writes it after a key's `=`, on one line:
    ## `"text"`, `42`, `1.5`, `[1, 2]`, `{ name = "demo" }`.
    ##
    ## @returns the TOML text
    to_string(): String {
        return _toml_write_inline(this);
    }

    ## Returns a table as a TOML document: its plain members as `key =
    ## value` lines, then each table member under a `[header]` and each
    ## array of tables as `[[header]]` sections, nested tables after their
    ## parent's members.
    ##
    ## @returns the document text, ending with a line break unless it is
    ##   empty
    ## @panics if this is not a table ("TomlValue.to_document needs a
    ##   table")
    ## @example
    ##     import toml;
    ##
    ##     var root = toml.TomlValue.table();
    ##     root["title"] = toml.TomlValue.String("demo");
    ##     var server = toml.TomlValue.table();
    ##     server["port"] = toml.TomlValue.Integer(8080);
    ##     root["server"] = server;
    ##     assert(root.to_document() == "title = \"demo\"\n\n[server]\nport = 8080\n", "a document");
    to_document(): String {
        if (this is Table(members)) {
            return _toml_write_document(members);
        }
        panic($"TomlValue.to_document needs a table, not {_toml_kind(this)}");
        return "";
    }
}

# How an error names a value's kind: "a string", "an integer".
export _toml_kind(value: TomlValue): String {
    var name = value.type_name();
    if (name == "integer" || name == "array") {
        return $"an {name}";
    }
    return $"a {name}";
}
