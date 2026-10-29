# `\x80` to `\xFF` in a `StringConstant` are raw bytes (#298): a static
# byte table, read with `size` and `byte_at`.
const TABLE = "\x00\x7F\x80\xFF";

first_byte(bytes: StringConstant): int {
    return bytes.byte_at(0) as int;
}

main(): int {
    if (TABLE.size != 4) { return -1; }
    if (TABLE.byte_at(2) as int != 0x80 or TABLE.byte_at(3) as int != 0xFF) { return -2; }
    if (TABLE.length != 0) { return -3; }
    if (TABLE.is_empty) { return -4; }
    if (first_byte("\xFE\x01") != 0xFE) { return -5; }
    StringConstant one = "\x80";
    StringConstant two = "\x80\x81";
    if (one == two or !(one == "\x80")) { return -6; }
    # Bytes that make valid UTF-8 are text, in a `String` too.
    String accent = "caf\xC3\xA9";
    if (accent != "café" or accent.length != 4) { return -7; }
    return 0;
}
