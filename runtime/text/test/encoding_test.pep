# text: UTF-8 validation, code points and encoding; UTF-16, ASCII and code
# page 437 encode/decode, strict and lossy.
import text;

[Test]
text_utf8_reads_and_appends_code_points() {
    var s = "aé€𝄞";
    expect_true(text.Utf8.find_invalid(s).is_empty());
    var bytes = Array<u8>();
    bytes.append(104);
    bytes.append(105);
    bytes.append(192);
    var raw = String(unsafe_cast<__ptr<char>>(bytes._data), 3);
    expect_equal(text.Utf8.find_invalid(raw).value(), 2);
    var (a, a_run) = text.Utf8.code_point_at(s, 0);
    expect_equal(a, 97);
    expect_equal(a_run, 1);
    var (e, e_run) = text.Utf8.code_point_at(s, 1);
    expect_equal(e, 233);
    expect_equal(e_run, 2);
    var (euro, euro_run) = text.Utf8.code_point_at(s, 3);
    expect_equal(euro, 8364);
    expect_equal(euro_run, 3);
    var (clef, clef_run) = text.Utf8.code_point_at(s, 6);
    expect_equal(clef, 119070);
    expect_equal(clef_run, 4);
    var out = Array<u8>();
    text.Utf8.append_code_point(out, 97);
    text.Utf8.append_code_point(out, 233);
    text.Utf8.append_code_point(out, 8364);
    text.Utf8.append_code_point(out, 119070);
    expect_equal(text.Utf8.decode(out).value(), s);
}

[Test]
text_module_encodes_and_decodes() {
    var s = "héllo €𝄞";
    var b = text.Utf8.encode(s);
    expect_equal(text.Utf8.decode(b).value(), s);
    var bad = Array<u8>();
    bad.append(104);
    bad.append(255);
    expect_true(text.Utf8.decode(bad).is_empty());
    expect_equal(text.Utf8.decode_lossy(bad), "h\u{FFFD}");
    var little_endian = text.Utf16.encode(s);
    expect_equal(little_endian.count, 18);
    expect_equal(text.Utf16.decode(little_endian).value(), s);
    var big_endian = text.Utf16.encode(s, true);
    expect_equal(big_endian[0], 0);
    expect_equal(big_endian[1], 104);
    expect_equal(text.Utf16.decode(big_endian, true).value(), s);
    var lone = Array<u8>();
    lone.append(0);
    lone.append(216);
    expect_true(text.Utf16.decode(lone).is_empty());
    expect_equal(text.Utf16.decode_lossy(lone), "\u{FFFD}");
    expect_equal(text.Ascii.encode("ok").value().count, 2);
    expect_true(text.Ascii.encode(s).is_empty());
    var question = text.Ascii.encode_lossy("aé€");
    expect_equal(question.count, 3);
    expect_equal(question[1], 63);
    expect_true(text.Ascii.decode(bad).is_empty());
    expect_equal(text.Ascii.decode_lossy(bad), "h\u{FFFD}");
    var all = Array<u8>();
    for (var value in 0..256) {
        all.append(value as u8);
    }
    var dos = text.CodePage437.decode(all);
    expect_true(text.CodePage437.encode(dos).value() == all);
    expect_equal(text.CodePage437.decode(text.CodePage437.encode("Ç░α").value()), "Ç░α");
    expect_true(text.CodePage437.encode("a€").is_empty());
    expect_true(text.CodePage437.encode_lossy("a€b") == "a?b".bytes());
}

# Round trips through every lossy path release what they make (the runner's
# leak check catches a miss).
[Test]
text_lossy_round_trips_release_everything() {
    var s = "héllo €𝄞";
    var x = text.Utf16.decode_lossy(text.Utf16.encode(s));
    var y = text.Ascii.encode_lossy(x);
    var z = text.CodePage437.decode(text.CodePage437.encode_lossy(x));
    expect_equal(x, s);
}

# Checks that the String holding the bytes `values`, which are not valid
# UTF-8, encodes (and so ends) to the text `replaced`, as
# `Utf8.decode_lossy` reads the bytes: U+FFFD for each byte that starts no
# sequence. A String made from C memory can hold such bytes
# (pep-lang/pepper#165).
_text_check_invalid(values: int[], replaced: String) {
    var bytes = Array<u8>();
    for (var value in values) {
        bytes.append(value as u8);
    }
    var raw = String(unsafe_cast<__ptr<char>>(bytes._data), bytes.count);
    expect_equal(text.Utf8.decode_lossy(bytes), replaced);
    expect_equal(text.Utf16.decode(text.Utf16.encode(raw)).value(), replaced);
    expect_equal(text.Utf16.decode(text.Utf16.encode(raw, true), true).value(), replaced);
    expect_equal(text.Ascii.encode_lossy(raw).count, replaced.length);
}

[Test]
text_encoding_invalid_utf8_ends_with_a_replacement_per_bad_byte() {
    _text_check_invalid([97, 226, 130, 98], "a\u{FFFD}\u{FFFD}b");                       # truncated '€'
    _text_check_invalid([226], "\u{FFFD}");                                              # truncated at the end
    _text_check_invalid([97, 128, 98], "a\u{FFFD}b");                                    # lone continuation byte
    _text_check_invalid([97, 192, 175, 98], "a\u{FFFD}\u{FFFD}b");                       # overlong '/'
    _text_check_invalid([97, 237, 160, 128, 98], "a\u{FFFD}\u{FFFD}\u{FFFD}b");          # U+D800
    _text_check_invalid([97, 244, 144, 128, 128], "a\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}");  # past U+10FFFF
}
