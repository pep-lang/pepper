# HPACK (RFC 7541), the header compression of HTTP/2: the static table, a
# dynamic table for each direction, the integer and string encodings, and
# the Huffman code. An `_HpackEncoder` keeps the table of the fields this
# side sends and an `_HpackDecoder` the table of the fields it receives, so
# an HTTP/2 connection has one of each.

import io;
import "wire";

# The dynamic table size HTTP/2 starts with (SETTINGS_HEADER_TABLE_SIZE).
const _HPACK_DEFAULT_TABLE_SIZE: ulong = 4096;

# The size RFC 7541 counts for an entry besides its name and value.
const _HPACK_ENTRY_OVERHEAD: ulong = 32;

# The longest Huffman code, in bits (EOS's).
const _HPACK_LONGEST_CODE: ulong = 30;

# The Huffman code's end-of-string symbol, which never appears in a string.
const _HPACK_EOS: uint = 256;

# One header field: a lowercase name and a value.
struct _HpackField {
    var name: String;
    var value: String;

    construct(name: String, value: String) {
        this.name = name;
        this.value = value;
    }
}

# The size an entry for `field` takes in a dynamic table.
_hpack_entry_size(field: _HpackField): ulong {
    return field.name.size + field.value.size + _HPACK_ENTRY_OVERHEAD;
}

# The static table (RFC 7541 appendix A): index 1 is element 0.
_hpack_static_table(): _HpackField[] {
    # format: off
    _HpackField[] table = [
        _HpackField(":authority", ""),
        _HpackField(":method", "GET"),
        _HpackField(":method", "POST"),
        _HpackField(":path", "/"),
        _HpackField(":path", "/index.html"),
        _HpackField(":scheme", "http"),
        _HpackField(":scheme", "https"),
        _HpackField(":status", "200"),
        _HpackField(":status", "204"),
        _HpackField(":status", "206"),
        _HpackField(":status", "304"),
        _HpackField(":status", "400"),
        _HpackField(":status", "404"),
        _HpackField(":status", "500"),
        _HpackField("accept-charset", ""),
        _HpackField("accept-encoding", "gzip, deflate"),
        _HpackField("accept-language", ""),
        _HpackField("accept-ranges", ""),
        _HpackField("accept", ""),
        _HpackField("access-control-allow-origin", ""),
        _HpackField("age", ""),
        _HpackField("allow", ""),
        _HpackField("authorization", ""),
        _HpackField("cache-control", ""),
        _HpackField("content-disposition", ""),
        _HpackField("content-encoding", ""),
        _HpackField("content-language", ""),
        _HpackField("content-length", ""),
        _HpackField("content-location", ""),
        _HpackField("content-range", ""),
        _HpackField("content-type", ""),
        _HpackField("cookie", ""),
        _HpackField("date", ""),
        _HpackField("etag", ""),
        _HpackField("expect", ""),
        _HpackField("expires", ""),
        _HpackField("from", ""),
        _HpackField("host", ""),
        _HpackField("if-match", ""),
        _HpackField("if-modified-since", ""),
        _HpackField("if-none-match", ""),
        _HpackField("if-range", ""),
        _HpackField("if-unmodified-since", ""),
        _HpackField("last-modified", ""),
        _HpackField("link", ""),
        _HpackField("location", ""),
        _HpackField("max-forwards", ""),
        _HpackField("proxy-authenticate", ""),
        _HpackField("proxy-authorization", ""),
        _HpackField("range", ""),
        _HpackField("referer", ""),
        _HpackField("refresh", ""),
        _HpackField("retry-after", ""),
        _HpackField("server", ""),
        _HpackField("set-cookie", ""),
        _HpackField("strict-transport-security", ""),
        _HpackField("transfer-encoding", ""),
        _HpackField("user-agent", ""),
        _HpackField("vary", ""),
        _HpackField("via", ""),
        _HpackField("www-authenticate", ""),
    ];
    # format: on
    return table;
}

# The length in bits of each symbol's Huffman code (RFC 7541 appendix B),
# symbols 0 through 256. The code is canonical, so the lengths define it.
_hpack_code_lengths(): u8[] {
    # format: off
    u8[] lengths = [
        13, 23, 28, 28, 28, 28, 28, 28, 28, 24, 30, 28, 28, 30, 28, 28,
        28, 28, 28, 28, 28, 28, 30, 28, 28, 28, 28, 28, 28, 28, 28, 28,
        6, 10, 10, 12, 13, 6, 8, 11, 10, 10, 8, 11, 8, 6, 6, 6,
        5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 7, 8, 15, 6, 12, 10,
        13, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
        7, 7, 7, 7, 7, 7, 7, 7, 8, 7, 8, 13, 19, 13, 14, 6,
        15, 5, 6, 5, 6, 5, 6, 6, 6, 5, 7, 7, 6, 6, 6, 5,
        6, 7, 6, 5, 5, 6, 7, 7, 7, 7, 7, 15, 11, 14, 13, 28,
        20, 22, 20, 20, 22, 22, 22, 23, 22, 23, 23, 23, 23, 23, 24, 23,
        24, 24, 22, 23, 24, 23, 23, 23, 23, 21, 22, 23, 22, 23, 23, 24,
        22, 21, 20, 22, 22, 23, 23, 21, 23, 22, 22, 24, 21, 22, 23, 23,
        21, 21, 22, 21, 23, 22, 23, 23, 20, 22, 22, 22, 23, 22, 22, 23,
        26, 26, 20, 19, 22, 23, 22, 25, 26, 26, 26, 27, 27, 26, 24, 25,
        19, 21, 26, 27, 27, 26, 27, 24, 21, 21, 26, 26, 28, 27, 27, 27,
        20, 24, 20, 21, 22, 21, 21, 23, 22, 22, 25, 25, 24, 24, 26, 23,
        26, 27, 26, 26, 27, 27, 27, 27, 27, 28, 27, 27, 27, 27, 27, 26,
        30,
    ];
    # format: on
    return lengths;
}

# A list of `count` zeros.
_hpack_zeros(count: ulong): uint[] {
    var result = Array<uint>(count);
    while (result.count < count) {
        result.append(0);
    }
    return result;
}

# The Huffman code, for encoding and decoding.
struct _HpackHuffman {
    # Each symbol's code length and code.
    var lengths: u8[];
    var codes: uint[];
    # For each code length: how many codes have it, the first of them, and
    # where their symbols start in `symbols`.
    var _counts: uint[];
    var _first: uint[];
    var _offsets: uint[];
    # The symbols in canonical order: by code length, then by symbol.
    var _symbols: uint[];

    construct() {
        lengths = _hpack_code_lengths();
        _counts = _hpack_zeros(_HPACK_LONGEST_CODE + 1);
        for (var length in lengths) {
            _counts[length as ulong] += 1;
        }
        _first = _hpack_zeros(_HPACK_LONGEST_CODE + 1);
        _offsets = _hpack_zeros(_HPACK_LONGEST_CODE + 1);
        uint code = 0;
        uint offset = 0;
        ulong length = 1;
        while (length <= _HPACK_LONGEST_CODE) {
            _first[length] = code;
            _offsets[length] = offset;
            code = (code + _counts[length]) << 1;
            offset += _counts[length];
            length += 1;
        }
        # Symbols of one length take consecutive codes in symbol order.
        var next = _first.clone();
        var placed = _offsets.clone();
        codes = _hpack_zeros(lengths.count);
        _symbols = _hpack_zeros(lengths.count);
        ulong symbol = 0;
        while (symbol < lengths.count) {
            var size = lengths[symbol] as ulong;
            codes[symbol] = next[size];
            next[size] += 1;
            _symbols[placed[size] as ulong] = symbol as uint;
            placed[size] += 1;
            symbol += 1;
        }
    }

    # The number of bytes `data[start..start + size]` takes encoded.
    encoded_size(data: __ptr<u8>, size: ulong): ulong {
        ulong bits = 0;
        ulong index = 0;
        while (index < size) {
            bits += lengths[data[index] as ulong] as ulong;
            index += 1;
        }
        return (bits + 7) / 8;
    }

    # Appends the `size` bytes at `data`, encoded, to `out`, padded with
    # the high bits of EOS (all ones).
    encode(data: __ptr<u8>, size: ulong, out: u8[]) {
        ulong pending = 0;
        ulong bits = 0;
        ulong index = 0;
        while (index < size) {
            var symbol = data[index] as ulong;
            var length = lengths[symbol] as ulong;
            pending = (pending << length) | (codes[symbol] as ulong);
            bits += length;
            while (bits >= 8) {
                bits -= 8;
                out.append(((pending >> bits) & 0xff) as u8);
            }
            pending &= ((1 as ulong) << bits) - 1;
            index += 1;
        }
        if (bits > 0) {
            var pad = 8 - bits;
            out.append((((pending << pad) | (((1 as ulong) << pad) - 1)) & 0xff) as u8);
        }
    }

    # Decodes the `size` bytes at `data` into `out`; an error when they hold
    # EOS, a code that is not in the table, or padding longer than 7 bits or
    # not all ones.
    decode(data: __ptr<u8>, size: ulong, out: u8[]): io.IoResult<void> {
        # shortcut: one bit at a time; switch to a table of 8-bit steps if headers ever show up in a profile.
        uint code = 0;
        ulong length = 0;
        ulong index = 0;
        while (index < size) {
            var byte = data[index] as uint;
            uint bit = 8;
            while (bit > 0) {
                bit -= 1;
                code = (code << 1) | ((byte >> bit) & 1);
                length += 1;
                var within = code - _first[length];
                if (code >= _first[length] && within < _counts[length]) {
                    var symbol = _symbols[(_offsets[length] + within) as ulong];
                    if (symbol == _HPACK_EOS) {
                        return io.IoResult<void>.err(_http_error("a Huffman-coded string holds EOS"));
                    }
                    out.append(symbol as u8);
                    code = 0;
                    length = 0;
                    continue;
                }
                if (length == _HPACK_LONGEST_CODE) {
                    return io.IoResult<void>.err(_http_error("a Huffman-coded string holds an unknown code"));
                }
            }
            index += 1;
        }
        if (length > 7 || code != ((1 as uint) << (length as uint)) - 1) {
            return io.IoResult<void>.err(_http_error("a Huffman-coded string has bad padding"));
        }
        return io.IoResult<void>.ok();
    }
}

# A dynamic table: the fields added most recently, which take at most
# `capacity` bytes in all (RFC 7541 section 4).
struct _HpackTable {
    # Oldest first: the newest has the lowest index.
    var _entries: _HpackField[];
    var _static: _HpackField[];
    # The size of the entries, and the most they may take.
    var size: ulong;
    var capacity: ulong;

    construct(capacity: ulong) {
        _entries = Array<_HpackField>();
        _static = _hpack_static_table();
        size = 0;
        this.capacity = capacity;
    }

    # The number of entries in the dynamic table.
    var count: ulong {
        get {
            return _entries.count;
        }
    }

    # The field at `index`: 1 through 61 are the static table, and the
    # dynamic table follows, newest first. None when there is no such
    # entry.
    field(index: ulong): _HpackField? {
        if (index == 0) {
            return Optional<_HpackField>.Empty;
        }
        if (index <= _static.count) {
            return Optional<_HpackField>.Value(_static[index - 1]);
        }
        var age = index - _static.count - 1;
        if (age >= _entries.count) {
            return Optional<_HpackField>.Empty;
        }
        return Optional<_HpackField>.Value(_entries[_entries.count - 1 - age]);
    }

    # The lowest index whose entry has `field`'s name, and whether its value
    # matches too: the first entry that matches both when one does. 0 when
    # no entry has the name.
    find(field: _HpackField): (ulong, bool) {
        ulong named = 0;
        ulong index = 1;
        while (index <= _static.count + _entries.count) {
            var entry = this.field(index).value();
            if (entry.name == field.name) {
                if (entry.value == field.value) {
                    return (index, true);
                }
                if (named == 0) {
                    named = index;
                }
            }
            index += 1;
        }
        return (named, false);
    }

    # Adds `field` as the newest entry, evicting the oldest ones to make
    # room. A field larger than the capacity empties the table and is not
    # added.
    add(field: _HpackField) {
        var needed = _hpack_entry_size(field);
        while (_entries.count > 0 && size + needed > capacity) {
            size -= _hpack_entry_size(_entries.remove_at(0));
        }
        if (needed > capacity) {
            return;
        }
        _entries.append(field);
        size += needed;
    }

    # Sets the capacity, evicting the oldest entries until the rest fit.
    resize(capacity: ulong) {
        this.capacity = capacity;
        while (size > capacity) {
            size -= _hpack_entry_size(_entries.remove_at(0));
        }
    }
}

# Appends `value` to `out` as an HPACK integer with an `prefix`-bit prefix,
# the first byte's other bits set to `flags` (RFC 7541 section 5.1).
_hpack_append_integer(out: u8[], flags: u8, prefix: ulong, value: ulong) {
    var limit = ((1 as ulong) << prefix) - 1;
    if (value < limit) {
        out.append(flags | (value as u8));
        return;
    }
    out.append(flags | (limit as u8));
    var rest = value - limit;
    while (rest >= 128) {
        out.append(((rest & 0x7f) | 0x80) as u8);
        rest = rest >> 7;
    }
    out.append(rest as u8);
}

# Appends `text` to `out` as an HPACK string literal: Huffman-coded when
# `huffman` is true and that is no longer (RFC 7541 section 5.2).
_hpack_append_string(out: u8[], text: String, huffman: _HpackHuffman?) {
    var data = unsafe_cast<__ptr<u8>>(text.c_str());
    if (!huffman.is_empty()) {
        var code = huffman.value();
        var coded = code.encoded_size(data, text.size);
        if (coded <= text.size) {
            _hpack_append_integer(out, 0x80, 7, coded);
            code.encode(data, text.size, out);
            return;
        }
    }
    _hpack_append_integer(out, 0, 7, text.size);
    out._append_raw(data, text.size);
}

# The header block being decoded, and how much of it has been.
struct _HpackInput {
    var data: u8[];
    var at: ulong;

    construct(data: u8[]) {
        this.data = data;
        at = 0;
    }

    # Reads an integer with a `prefix`-bit prefix, starting in the current
    # byte. Integers beyond 32 bits are an error: none means anything to
    # HTTP/2.
    integer(prefix: ulong): io.IoResult<ulong> {
        if (at >= data.count) {
            return io.IoResult<ulong>.err(_http_error("a header block ends in the middle of an integer"));
        }
        var limit = ((1 as ulong) << prefix) - 1;
        var value = (data[at] as ulong) & limit;
        at += 1;
        if (value < limit) {
            return io.IoResult<ulong>.ok(value);
        }
        ulong shift = 0;
        while (true) {
            if (at >= data.count) {
                return io.IoResult<ulong>.err(_http_error("a header block ends in the middle of an integer"));
            }
            if (shift > 28) {
                return io.IoResult<ulong>.err(_http_error("a header block holds an integer that is too large"));
            }
            var next = data[at] as ulong;
            at += 1;
            value += (next & 0x7f) << shift;
            shift += 7;
            if ((next & 0x80) == 0) {
                return io.IoResult<ulong>.ok(value);
            }
        }
        return io.IoResult<ulong>.ok(value);
    }

    # Reads a string literal, Huffman-decoding it when it is coded.
    string(huffman: _HpackHuffman): io.IoResult<String> {
        if (at >= data.count) {
            return io.IoResult<String>.err(_http_error("a header block ends before a string"));
        }
        var coded = (data[at] & 0x80) != 0;
        var length = this.integer(7);
        if (length.is_err()) {
            return io.IoResult<String>.err(length.error());
        }
        var size = length.value();
        if (size > data.count - at) {
            return io.IoResult<String>.err(_http_error("a header block ends in the middle of a string"));
        }
        var start = data._data + at;
        at += size;
        if (!coded) {
            return io.IoResult<String>.ok(_http_line_text(start, size));
        }
        var decoded = Array<u8>(size * 2);
        var done = huffman.decode(start, size, decoded);
        if (done.is_err()) {
            return io.IoResult<String>.err(done.error());
        }
        return io.IoResult<String>.ok(_http_line_text(decoded._data, decoded.count));
    }
}

# Decodes the header blocks one side of a connection receives.
struct _HpackDecoder {
    var _table: _HpackTable;
    var _huffman: _HpackHuffman;
    # The largest table the encoder may use: the SETTINGS_HEADER_TABLE_SIZE
    # this side sent.
    var limit: ulong;

    construct(limit: ulong = _HPACK_DEFAULT_TABLE_SIZE) {
        _table = _HpackTable(limit);
        _huffman = _HpackHuffman();
        this.limit = limit;
    }

    # Decodes one whole header block (the fragments of a HEADERS frame and
    # its CONTINUATION frames, joined) into its fields, in order. An error
    # is a COMPRESSION_ERROR: the table may be left part-updated, so the
    # connection cannot go on.
    decode(block: u8[]): io.IoResult<_HpackField[]> {
        var input = _HpackInput(block);
        var fields = Array<_HpackField>();
        while (input.at < block.count) {
            var first = block[input.at];
            if ((first & 0x80) != 0) {
                var index = input.integer(7);
                if (index.is_err()) {
                    return io.IoResult<_HpackField[]>.err(index.error());
                }
                var found = _table.field(index.value());
                if (found.is_empty()) {
                    return io.IoResult<_HpackField[]>.err(
                        _http_error($"a header block refers to index {index.value()}, which is not in the table")
                    );
                }
                fields.append(found.value());
                continue;
            }
            if ((first & 0xe0) == 0x20) {
                # A dynamic table size update, allowed only before the fields.
                if (fields.count > 0) {
                    return io.IoResult<_HpackField[]>.err(
                        _http_error("a header block changes the table size after a field")
                    );
                }
                var capacity = input.integer(5);
                if (capacity.is_err()) {
                    return io.IoResult<_HpackField[]>.err(capacity.error());
                }
                if (capacity.value() > limit) {
                    return io.IoResult<_HpackField[]>.err(
                        _http_error(
                            $"a header block sets the table size to {capacity.value()}, above the limit of {limit}"
                        )
                    );
                }
                _table.resize(capacity.value());
                continue;
            }
            # A literal: with incremental indexing (01), or without (0000)
            # or never (0001) indexed.
            var indexing = (first & 0xc0) == 0x40;
            ulong prefix = 4;
            if (indexing) {
                prefix = 6;
            }
            var field = this._literal(input, prefix);
            if (field.is_err()) {
                return io.IoResult<_HpackField[]>.err(field.error());
            }
            if (indexing) {
                _table.add(field.value());
            }
            fields.append(field.value());
        }
        return io.IoResult<_HpackField[]>.ok(fields);
    }

    # Reads a literal field whose name index has a `prefix`-bit prefix.
    _literal(input: _HpackInput, prefix: ulong): io.IoResult<_HpackField> {
        var index = input.integer(prefix);
        if (index.is_err()) {
            return io.IoResult<_HpackField>.err(index.error());
        }
        var name = "";
        if (index.value() == 0) {
            var read = input.string(_huffman);
            if (read.is_err()) {
                return io.IoResult<_HpackField>.err(read.error());
            }
            name = read.value();
        } else {
            var found = _table.field(index.value());
            if (found.is_empty()) {
                return io.IoResult<_HpackField>.err(
                    _http_error($"a header block refers to index {index.value()}, which is not in the table")
                );
            }
            name = found.value().name;
        }
        var value = input.string(_huffman);
        if (value.is_err()) {
            return io.IoResult<_HpackField>.err(value.error());
        }
        return io.IoResult<_HpackField>.ok(_HpackField(name, value.value()));
    }
}

# Encodes the header blocks one side of a connection sends.
struct _HpackEncoder {
    var _table: _HpackTable;
    var _huffman: _HpackHuffman;
    # Whether strings are Huffman-coded when that makes them no longer.
    var huffman: bool;
    # The smallest capacity set since the last block, which the next one
    # must announce before the current one, when `_resized`.
    var _resized: bool;
    var _smallest: ulong;

    construct(capacity: ulong = _HPACK_DEFAULT_TABLE_SIZE) {
        _table = _HpackTable(capacity);
        _huffman = _HpackHuffman();
        huffman = true;
        _resized = false;
        _smallest = capacity;
    }

    # Sets the table's capacity, for a new SETTINGS_HEADER_TABLE_SIZE from
    # the peer; the next block announces it.
    resize(capacity: ulong) {
        if (!_resized || capacity < _smallest) {
            _smallest = capacity;
        }
        _resized = true;
        _table.resize(capacity);
    }

    # Appends the header block for `fields` to `out`. Names must already be
    # lowercase. Credentials are never indexed (RFC 7541 section 7.1.3), and
    # a field too large for the table is sent without indexing.
    encode(fields: _HpackField[], out: u8[]) {
        if (_resized) {
            if (_smallest < _table.capacity) {
                _hpack_append_integer(out, 0x20, 5, _smallest);
            }
            _hpack_append_integer(out, 0x20, 5, _table.capacity);
            _resized = false;
        }
        var code = Optional<_HpackHuffman>.Empty;
        if (huffman) {
            code = Optional<_HpackHuffman>.Value(_huffman);
        }
        for (var field in fields) {
            var (index, matched) = _table.find(field);
            if (matched) {
                _hpack_append_integer(out, 0x80, 7, index);
                continue;
            }
            var sensitive = field.name == "authorization" || field.name == "proxy-authorization";
            if (sensitive) {
                _hpack_append_integer(out, 0x10, 4, index);
            } else if (_hpack_entry_size(field) > _table.capacity) {
                _hpack_append_integer(out, 0, 4, index);
            } else {
                _hpack_append_integer(out, 0x40, 6, index);
                _table.add(field);
            }
            if (index == 0) {
                _hpack_append_string(out, field.name, code);
            }
            _hpack_append_string(out, field.value, code);
        }
    }
}
