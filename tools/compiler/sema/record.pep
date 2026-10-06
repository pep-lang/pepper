## The bytes of a checked unit's record, as `record_codec.pep` writes and
## reads them: numbers as LEB128 varints, each distinct string once.
##
## A record is a header (`MAGIC`), the number of strings and each one's size
## in bytes, the size of the values, the values, then the strings' UTF-8
## text one after another. A value refers to a string by its place in that
## list. A location's file is written as its slot in `RecordOut.files`, so a
## record loads into a program whose files sit in other places.

import compiler.ast;
import [Utf8] from text;
import [Loc, NO_FILE] from "loc";

## What every record starts with: the format's name and version.
export const MAGIC = "pepper record 1\n";

## A record being written.
export struct RecordOut {
    ## The values written so far.
    var values: u8[] = Array<u8>();
    ## For each program file a location may name, its slot in the record,
    ## from 0. Empty: every file is its own slot.
    var files: HashMap<uint, uint> = HashMap<uint, uint>();
    # Each string's place in the list, by its text.
    var _places: HashMap<String, ulong> = HashMap<String, ulong>();
    # The strings' sizes, in their order.
    var _sizes: ulong[] = Array<ulong>();
    # The strings' text, in their order.
    var _text: StringBuilder = StringBuilder();

    construct() {}

    ## Writes an unsigned number.
    ##
    ## @param value the number
    unsigned(value: ulong) {
        var rest = value;
        while (rest >= 0x80) {
            values.append((rest & 0x7F | 0x80) as u8);
            rest = rest >> 7;
        }
        values.append(rest as u8);
    }

    ## Writes a signed number.
    ##
    ## @param value the number
    signed(value: long) {
        unsigned(((value << 1) ^ (value >> 63)) as ulong);
    }

    ## Writes a boolean.
    ##
    ## @param value the boolean
    flag(value: bool) {
        values.append(value ? 1 : 0);
    }

    ## Writes a floating-point number, by its bits.
    ##
    ## @param value the number
    number(value: double) {
        unsigned(unsafe_cast<ulong>(value));
    }

    ## Writes a string: its place in the list, which it joins when new.
    ##
    ## @param value the string
    text(value: String) {
        var place = _places.try_get(value);
        if (place.is_value()) {
            unsigned(place.value());
            return;
        }
        var next = _sizes.count;
        _places[value] = next;
        _sizes.append(value.size);
        _text.append(value);
        unsigned(next);
    }

    ## Writes a location: its file's slot (0 for none, else the slot plus
    ## one) and its bytes.
    ##
    ## @param value the location
    loc(value: Loc) {
        if (value.file == NO_FILE) {
            unsigned(0);
        } else if (files.is_empty) {
            unsigned(value.file as ulong + 1);
        } else {
            unsigned(files[value.file] as ulong + 1);
        }
        unsigned(value.span.start);
        unsigned(value.span.end);
    }

    ## Returns the whole record.
    ##
    ## @returns the bytes
    finish(): u8[] {
        var head = RecordOut();
        for (var byte in MAGIC.bytes()) {
            head.values.append(byte);
        }
        head.unsigned(_sizes.count);
        for (var size in _sizes) {
            head.unsigned(size);
        }
        head.unsigned(values.count);
        var out = head.values;
        out.append_all(values);
        out.append_all(_text.to_string().bytes());
        return out;
    }
}

## A record being read.
export struct RecordIn {
    ## For each slot in the record, the program file it is now. Empty:
    ## every slot is the file of its number.
    var files: uint[] = Array<uint>();
    ## Why reading failed; empty while it has not.
    var error: String = "";
    # The record.
    var _data: u8[];
    # The next byte of `_data` to read.
    var _next: ulong;
    # Where the values end.
    var _end: ulong;
    # The strings, in their order.
    var _strings: String[] = Array<String>();

    ## Starts reading `data`, a whole record. A record that is not one
    ## leaves `error` set and reads as zeros.
    ##
    ## @param data the record
    construct(data: u8[]) {
        _data = data;
        _end = data.count;
        _open();
    }

    # Reads the header and the strings.
    _open() {
        var magic = MAGIC.bytes();
        if (_data.count < magic.count) {
            error = "not a record";
            return;
        }
        for (var i in 0..magic.count) {
            if (_data[i] != magic[i]) {
                error = "not a record of this version";
                return;
            }
        }
        _next = magic.count;
        var count = this.count();
        var sizes = Array<ulong>();
        for (var _ in 0..count) {
            sizes.append(unsigned());
        }
        var size = unsigned();
        if (error != "" or _next + size > _data.count) {
            error = "a truncated record";
            return;
        }
        var text_start = _next + size;
        var bytes = Array<u8>();
        for (var i in text_start.._data.count) {
            bytes.append(_data[i]);
        }
        var decoded = Utf8.decode(bytes);
        if (!decoded.is_value()) {
            error = "a record whose strings are not UTF-8";
            return;
        }
        var all = decoded.value();
        ulong offset = 0;
        for (var s in sizes) {
            if (offset + s > all.size) {
                error = "a truncated record";
                return;
            }
            _strings.append(all.substr_bytes(offset, s));
            offset += s;
        }
        _end = text_start;
    }

    ## Reads an unsigned number.
    ##
    ## @returns the number, 0 past the end
    unsigned(): ulong {
        ulong value = 0;
        ulong shift = 0;
        while (_next < _end) {
            var byte = _data[_next];
            _next += 1;
            if (shift < 64) {
                value = value | (((byte & 0x7F) as ulong) << shift);
            }
            if (byte < 0x80) {
                return value;
            }
            shift += 7;
        }
        _fail("a truncated record");
        return 0;
    }

    ## Reads how many items follow: no more than bytes are left, since each
    ## takes at least one.
    ##
    ## @returns the count, 0 when the record is broken
    count(): ulong {
        var value = unsigned();
        if (value > _end - _next) {
            _fail("a count past the record's end");
            return 0;
        }
        return value;
    }

    ## Reads a signed number.
    ##
    ## @returns the number
    signed(): long {
        var raw = unsigned();
        return (raw >> 1) as long ^ -((raw & 1) as long);
    }

    ## Reads a boolean.
    ##
    ## @returns the boolean
    flag(): bool {
        if (_next >= _end) {
            _fail("a truncated record");
            return false;
        }
        var byte = _data[_next];
        _next += 1;
        return byte != 0;
    }

    ## Reads a floating-point number.
    ##
    ## @returns the number
    number(): double {
        return unsafe_cast<double>(unsigned());
    }

    ## Reads a string.
    ##
    ## @returns the string, empty when the record is broken
    text(): String {
        var place = unsigned();
        if (place >= _strings.count) {
            _fail("a string past the record's list");
            return "";
        }
        return _strings[place];
    }

    ## Reads a location.
    ##
    ## @returns the location
    loc(): Loc {
        var slot = unsigned();
        var start = unsigned();
        var end = unsigned();
        if (slot == 0) {
            var none = Loc.none();
            none.span = ast.Span(start, end);
            return none;
        }
        var file = (slot - 1) as uint;
        if (!files.is_empty) {
            if (file >= files.count) {
                _fail("a location in a file the record does not list");
                return Loc.none();
            }
            file = files[file];
        }
        return Loc.at(file, ast.Span(start, end));
    }

    ## Notes a value whose tag names no case of its type.
    ##
    ## @param type_name the type
    ## @param tag the tag read
    fail(type_name: String, tag: ulong) {
        _fail($"tag {tag} is no case of {type_name}");
    }

    ## Whether every value was read and nothing failed.
    ##
    ## @returns true for a whole, good record
    done(): bool {
        return error == "" and _next == _end;
    }

    _fail(why: String) {
        if (error == "") {
            error = why;
        }
        _next = _end;
    }
}
