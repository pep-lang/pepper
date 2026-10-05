# Byte-level text helpers. Spans in the syntax tree count bytes, so the
# reference and the checks work on byte offsets; every byte these look for
# is ASCII, which never occurs inside a multi-byte character.

# Whether `b` is ASCII whitespace: a space, tab, line feed, vertical tab,
# form feed or carriage return.
export is_ascii_space(b: byte): bool {
    return b == ' ' or b == '\t' or b == '\n' or b == '\r' or b == 11 or b == 12;
}

# Whether `b` is an ASCII letter or digit.
export is_ascii_alphanumeric(b: byte): bool {
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9');
}

# Whether `b` can be part of a word: a letter, a digit or `_`.
export is_word_byte(b: byte): bool {
    return is_ascii_alphanumeric(b) or b == '_';
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

# `text` from byte `start` up to byte `end`.
export slice(text: String, start: ulong, end: ulong): String {
    return text.substr_bytes(start, end - start);
}

# `text` from byte `start` to its end.
export slice_from(text: String, start: ulong): String {
    return text.substr_bytes(start, text.size - start);
}

# `text` with runs of whitespace collapsed to one space and none at either
# end.
export one_line(text: String): String {
    return " ".join(words(text));
}

# `text` with the first `from` replaced by `to`.
export replace_first(text: String, from: String, to: String): String {
    var at = text.find(from);
    if (at < 0) {
        return text;
    }
    return "".join([slice(text, 0, at as ulong), to, slice_from(text, at as ulong + from.size)]);
}

# `text` with Windows line ends (`\r\n`) read as `\n`, as a checkout with
# `core.autocrlf` may have written it.
export normalized(text: String): String {
    return text.replace("\r\n", "\n");
}

# The words of `text` that whitespace separates.
export words(text: String): String[] {
    var out = Array<String>();
    var i = skip_spaces(text, 0, text.size);
    while (i < text.size) {
        var end = find_space(text, i);
        out.append(slice(text, i, end));
        i = skip_spaces(text, end, text.size);
    }
    return out;
}
