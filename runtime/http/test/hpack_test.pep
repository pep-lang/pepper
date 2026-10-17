# HPACK against the examples of RFC 7541 appendix C: integers, single
# fields, and three requests and three responses each encoded in turn into
# one table, with and without Huffman coding. Then the errors a decoder
# must catch, and a round trip that evicts.

import digest;
import "../hpack";

# The bytes the hexadecimal `text` spells, ignoring spaces.
private bytes(text: String): u8[] {
    var digits = text.replace(" ", "");
    var result = Array<u8>(digits.size / 2);
    ulong index = 0;
    while (index < digits.size) {
        var high = _pep_hex_digit(digits.byte_at(index) as int);
        var low = _pep_hex_digit(digits.byte_at(index + 1) as int);
        result.append((high * 16 + low) as u8);
        index += 2;
    }
    return result;
}

# The fields `lines` lists, each `name: value`.
private fields(lines: String[]): _HpackField[] {
    var result = Array<_HpackField>();
    for (var line in lines) {
        var (name, value) = line.split_once(": ").value();
        result.append(_HpackField(name, value));
    }
    return result;
}

# `fields` as `name: value` lines, for comparing.
private lines(fields: _HpackField[]): String {
    var result = Array<String>();
    for (var field in fields) {
        result.append(field.name + ": " + field.value);
    }
    return "\n".join(result);
}

# Decodes `block` and checks it holds `expected`, leaving a table of `size`.
private expect_decodes(decoder: _HpackDecoder, block: String, expected: String[], size: ulong) {
    var decoded = decoder.decode(bytes(block));
    expect_true(decoded.is_ok());
    expect_equal(lines(decoded.value()), "\n".join(expected));
    expect_equal(decoder._table.size, size);
}

# Encodes `expected` and checks the block is `block`, leaving a table of `size`.
private expect_encodes(encoder: _HpackEncoder, expected: String[], block: String, size: ulong) {
    var out = Array<u8>();
    encoder.encode(fields(expected), out);
    expect_equal(digest.to_hex(out), block.replace(" ", ""));
    expect_equal(encoder._table.size, size);
}

private request_1(): String[] {
    return [":method: GET", ":scheme: http", ":path: /", ":authority: www.example.com"];
}

private request_2(): String[] {
    return [":method: GET", ":scheme: http", ":path: /", ":authority: www.example.com", "cache-control: no-cache"];
}

private request_3(): String[] {
    return [
        ":method: GET",
        ":scheme: https",
        ":path: /index.html",
        ":authority: www.example.com",
        "custom-key: custom-value"
    ];
}

private response_1(): String[] {
    return [
        ":status: 302",
        "cache-control: private",
        "date: Mon, 21 Oct 2013 20:13:21 GMT",
        "location: https://www.example.com"
    ];
}

private response_2(): String[] {
    return [
        ":status: 307",
        "cache-control: private",
        "date: Mon, 21 Oct 2013 20:13:21 GMT",
        "location: https://www.example.com"
    ];
}

private response_3(): String[] {
    return [
        ":status: 200",
        "cache-control: private",
        "date: Mon, 21 Oct 2013 20:13:22 GMT",
        "location: https://www.example.com",
        "content-encoding: gzip",
        "set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1",
    ];
}

[Test]
integers_with_a_prefix() {
    var out = Array<u8>();
    _hpack_append_integer(out, 0, 5, 10);    # C.1.1
    _hpack_append_integer(out, 0, 5, 1337);  # C.1.2
    _hpack_append_integer(out, 0, 8, 42);    # C.1.3
    expect_equal(digest.to_hex(out), "0a1f9a0a2a");

    var input = _HpackInput(out);
    expect_equal(input.integer(5).value(), 10);
    expect_equal(input.integer(5).value(), 1337);
    expect_equal(input.integer(8).value(), 42);
}

[Test]
single_fields() {
    # C.2.1 through C.2.4, each into a fresh table.
    expect_decodes(
        _HpackDecoder(),
        "400a 6375 7374 6f6d 2d6b 6579 0d63 7573 746f 6d2d 6865 6164 6572",
        ["custom-key: custom-header"],
        55
    );
    expect_decodes(_HpackDecoder(), "040c 2f73 616d 706c 652f 7061 7468", [":path: /sample/path"], 0);
    expect_decodes(_HpackDecoder(), "1008 7061 7373 776f 7264 0673 6563 7265 74", ["password: secret"], 0);
    expect_decodes(_HpackDecoder(), "82", [":method: GET"], 0);
}

[Test]
requests_without_huffman() {
    # C.3: three requests into one table.
    var decoder = _HpackDecoder();
    expect_decodes(decoder, "8286 8441 0f77 7777 2e65 7861 6d70 6c65 2e63 6f6d", request_1(), 57);
    expect_decodes(decoder, "8286 84be 5808 6e6f 2d63 6163 6865", request_2(), 110);
    expect_decodes(
        decoder, "8287 85bf 400a 6375 7374 6f6d 2d6b 6579 0c63 7573 746f 6d2d 7661 6c75 65", request_3(), 164
    );

    var encoder = _HpackEncoder();
    encoder.huffman = false;
    expect_encodes(encoder, request_1(), "8286 8441 0f77 7777 2e65 7861 6d70 6c65 2e63 6f6d", 57);
    expect_encodes(encoder, request_2(), "8286 84be 5808 6e6f 2d63 6163 6865", 110);
    expect_encodes(
        encoder, request_3(), "8287 85bf 400a 6375 7374 6f6d 2d6b 6579 0c63 7573 746f 6d2d 7661 6c75 65", 164
    );
}

[Test]
requests_with_huffman() {
    # C.4: the same requests, Huffman-coded.
    var decoder = _HpackDecoder();
    expect_decodes(decoder, "8286 8441 8cf1 e3c2 e5f2 3a6b a0ab 90f4 ff", request_1(), 57);
    expect_decodes(decoder, "8286 84be 5886 a8eb 1064 9cbf", request_2(), 110);
    expect_decodes(decoder, "8287 85bf 4088 25a8 49e9 5ba9 7d7f 8925 a849 e95b b8e8 b4bf", request_3(), 164);

    var encoder = _HpackEncoder();
    expect_encodes(encoder, request_1(), "8286 8441 8cf1 e3c2 e5f2 3a6b a0ab 90f4 ff", 57);
    expect_encodes(encoder, request_2(), "8286 84be 5886 a8eb 1064 9cbf", 110);
    expect_encodes(encoder, request_3(), "8287 85bf 4088 25a8 49e9 5ba9 7d7f 8925 a849 e95b b8e8 b4bf", 164);
}

private const PLAIN_1 = "4803 3330 3258 0770 7269 7661 7465 611d 4d6f 6e2c 2032 3120 4f63 7420 3230 3133 2032 303a 3133 3a32 3120 474d 546e 1768 7474 7073 3a2f 2f77 7777 2e65 7861 6d70 6c65 2e63 6f6d";
private const PLAIN_2 = "4803 3330 37c1 c0bf";
private const PLAIN_3 = "88c1 611d 4d6f 6e2c 2032 3120 4f63 7420 3230 3133 2032 303a 3133 3a32 3220 474d 54c0 5a04 677a 6970 7738 666f 6f3d 4153 444a 4b48 514b 425a 584f 5157 454f 5049 5541 5851 5745 4f49 553b 206d 6178 2d61 6765 3d33 3630 303b 2076 6572 7369 6f6e 3d31";

[Test]
responses_without_huffman() {
    # C.5: three responses into a 256-byte table, which evicts.
    var decoder = _HpackDecoder(256);
    expect_decodes(decoder, PLAIN_1, response_1(), 222);
    expect_decodes(decoder, PLAIN_2, response_2(), 222);
    expect_decodes(decoder, PLAIN_3, response_3(), 215);
    expect_equal(decoder._table.count, 3);

    var encoder = _HpackEncoder(256);
    encoder.huffman = false;
    expect_encodes(encoder, response_1(), PLAIN_1, 222);
    expect_encodes(encoder, response_2(), PLAIN_2, 222);
    expect_encodes(encoder, response_3(), PLAIN_3, 215);
}

private const CODED_1 = "4882 6402 5885 aec3 771a 4b61 96d0 7abe 9410 54d4 44a8 2005 9504 0b81 66e0 82a6 2d1b ff6e 919d 29ad 1718 63c7 8f0b 97c8 e9ae 82ae 43d3";
private const CODED_2 = "4883 640e ffc1 c0bf";
private const CODED_3 = "88c1 6196 d07a be94 1054 d444 a820 0595 040b 8166 e084 a62d 1bff c05a 839b d9ab 77ad 94e7 821d d7f2 e6c7 b335 dfdf cd5b 3960 d5af 2708 7f36 72c1 ab27 0fb5 291f 9587 3160 65c0 03ed 4ee5 b106 3d50 07";

[Test]
responses_with_huffman() {
    # C.6: the same responses, Huffman-coded.
    var decoder = _HpackDecoder(256);
    expect_decodes(decoder, CODED_1, response_1(), 222);
    expect_decodes(decoder, CODED_2, response_2(), 222);
    expect_decodes(decoder, CODED_3, response_3(), 215);

    var encoder = _HpackEncoder(256);
    expect_encodes(encoder, response_1(), CODED_1, 222);
    expect_encodes(encoder, response_2(), CODED_2, 222);
    expect_encodes(encoder, response_3(), CODED_3, 215);
}

[Test]
malformed_blocks_are_errors() {
    expect_true(_HpackDecoder().decode(bytes("80")).is_err());                   # index 0
    expect_true(_HpackDecoder().decode(bytes("be")).is_err());                   # an empty dynamic table
    expect_true(_HpackDecoder().decode(bytes("ff")).is_err());                   # an integer cut short
    expect_true(_HpackDecoder().decode(bytes("ffff ffff ffff 0f")).is_err());    # an integer past 32 bits
    expect_true(_HpackDecoder().decode(bytes("4005 6162")).is_err());            # a string cut short
    expect_true(_HpackDecoder().decode(bytes("3fe2 1f")).is_err());              # a table above the 4096 limit
    expect_true(_HpackDecoder().decode(bytes("823f e11f")).is_err());            # a size update after a field
    expect_true(_HpackDecoder().decode(bytes("4081 0081 00")).is_err());         # padding of 0 bits, not 1
    expect_true(_HpackDecoder().decode(bytes("4082 ffff 81ff")).is_err());       # padding longer than 7 bits
    expect_true(_HpackDecoder().decode(bytes("4084 ffff ffff 81ff")).is_err());  # EOS in the string
    expect_true(_HpackDecoder().decode(bytes("3fe1 1f82")).is_ok());             # the update itself is fine below the limit
}

[Test]
round_trips_through_a_small_table() {
    # Many fields through a table that holds only a few, so both sides
    # evict in step; a resize shrinks both, announced in the next block.
    var encoder = _HpackEncoder(200);
    var decoder = _HpackDecoder(200);
    var round = 0;
    while (round < 40) {
        var sent = [
            ":method: GET",
            ":path: /items/" + to_string(round % 7),
            "x-round: " + to_string(round),
            "authorization: Bearer secret",
            "x-big: " + "v".repeat(300),
        ];
        if (round == 20) {
            encoder.resize(64);
        }
        var block = Array<u8>();
        encoder.encode(fields(sent), block);
        var received = decoder.decode(block);
        expect_true(received.is_ok());
        expect_equal(lines(received.value()), "\n".join(sent));
        expect_equal(decoder._table.size, encoder._table.size);
        round += 1;
    }
    expect_equal(decoder._table.capacity, 64);
}
