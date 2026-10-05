# Byte-level text helpers for reading doc comments. Spans count bytes;
# every byte these look for is ASCII, which never occurs inside a
# multi-byte character. module.pep does not export them.

# Whether `b` is ASCII whitespace: a space, tab, line feed, vertical tab,
# form feed or carriage return.
export is_ascii_space(b: byte): bool {
    return b == ' ' or b == '\t' or b == '\n' or b == '\r' or b == 11 or b == 12;
}

# Whether `b` can be part of a word: a letter, a digit or `_`.
export is_word_byte(b: byte): bool {
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '_';
}

# The offset of the first `b` in `text` from `from` up to `to`; `to` when
# there is none.
export find_byte(text: String, b: byte, from: ulong, to: ulong): ulong {
    var i = from;
    while (i < to and text.byte_at(i) != b) {
        i += 1;
    }
    return i;
}

# The offset of the first whitespace in `text` from `from`; `text.size`
# when there is none.
export find_space(text: String, from: ulong): ulong {
    var i = from;
    while (i < text.size and !is_ascii_space(text.byte_at(i))) {
        i += 1;
    }
    return i;
}

# The offset of the first byte from `from` up to `to` that is not
# whitespace; `to` when there is none.
export skip_spaces(text: String, from: ulong, to: ulong): ulong {
    var i = from;
    while (i < to and is_ascii_space(text.byte_at(i))) {
        i += 1;
    }
    return i;
}

# Whether `prefix` is in `text` at `at`, ending at or before `end`.
export starts_with_at(text: String, at: ulong, end: ulong, prefix: String): bool {
    if (at + prefix.size > end) {
        return false;
    }
    ulong i = 0;
    while (i < prefix.size) {
        if (text.byte_at(at + i) != prefix.byte_at(i)) {
            return false;
        }
        i += 1;
    }
    return true;
}

# The start of the line that holds offset `end` (just after the last line
# feed before it), or 0.
export line_start_before(text: String, end: ulong): ulong {
    var i = end;
    while (i > 0 and text.byte_at(i - 1) != '\n') {
        i -= 1;
    }
    return i;
}
