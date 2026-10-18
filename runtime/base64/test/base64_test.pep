# The base64 module: RFC 4648's test vectors, both alphabets, with and
# without padding, and the inputs a strict decoder rejects.

import base64;

# The text of `text`'s base64 decoding, or "error".
decoded(text: String, url_safe: bool = false): String {
    var bytes = base64.decode(text, url_safe);
    if (bytes.is_err()) {
        return "error";
    }
    return String._from_bytes(bytes.value());
}

[Test]
encodes_rfc_4648_vectors() {
    var plain = ["", "f", "fo", "foo", "foob", "fooba", "foobar"];
    var padded = ["", "Zg==", "Zm8=", "Zm9v", "Zm9vYg==", "Zm9vYmE=", "Zm9vYmFy"];
    var unpadded = ["", "Zg", "Zm8", "Zm9v", "Zm9vYg", "Zm9vYmE", "Zm9vYmFy"];
    for (var i in 0..7) {
        var index = i as ulong;
        expect_equal(base64.encode(plain[index].bytes()), padded[index]);
        expect_equal(base64.encode(plain[index].bytes(), false, false), unpadded[index]);
        expect_equal(decoded(padded[index]), plain[index]);
        expect_equal(decoded(unpadded[index]), plain[index]);
    }
}

[Test]
url_safe_alphabet_replaces_plus_and_slash() {
    var bytes = [251 as u8, 255, 191];
    expect_equal(base64.encode(bytes), "+/+/");
    expect_equal(base64.encode(bytes, true), "-_-_");
    var back = base64.decode("-_-_", true).value();
    expect_equal(back.count, 3 as ulong);
    expect_equal(back[2], 191 as u8);
    expect_true(base64.decode("-_-_").is_err());
    expect_true(base64.decode("+/+/", true).is_err());
}

[Test]
round_trips_every_byte() {
    var bytes = Array<u8>();
    for (var i in 0..256) {
        bytes.append(i as u8);
    }
    for (var url_safe in [false, true]) {
        var back = base64.decode(base64.encode(bytes, url_safe), url_safe).value();
        expect_equal(back.count, 256 as ulong);
        for (var i in 0..256) {
            expect_equal(back[i as ulong], i as u8);
        }
    }
}

[Test]
rejects_what_is_not_base64() {
    expect_equal(decoded("Zm9v\n"), "error");  # whitespace
    expect_equal(decoded("Zm 9v"), "error");
    expect_equal(decoded("Z"), "error");  # a length no encoding gives
    expect_equal(decoded("Zm9vY"), "error");
    expect_equal(decoded("Zg="), "error");  # padding that does not complete the group
    expect_equal(decoded("Zg==="), "error");
    expect_equal(decoded("Z==="), "error");
    expect_equal(decoded("Zm=v"), "error");  # padding in the middle
    expect_equal(decoded("Zh=="), "error");  # unused bits set
    expect_equal(decoded("Zm9="), "error");
}
