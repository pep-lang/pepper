# Encodings: base64, hexadecimal, percent-escapes and form data, and UUIDs.
import base64;
import digest;
import uuid;

main(): int {
    # base64: an HTTP basic authentication header, and a URL-safe,
    # unpadded token as JSON Web Tokens write them.
    var credentials = base64.encode("ada:secret".bytes());
    assert(credentials == "YWRhOnNlY3JldA==", "standard, padded");
    var token = base64.encode([251, 255, 0], true, false);
    assert(token == "-_8A", "URL-safe, unpadded");
    assert(base64.decode(token, true).value()[0] == 251, "decoded");
    assert(base64.decode("not base64!").is_err(), "rejected");

    # Hexadecimal, both ways.
    assert(digest.from_hex(digest.to_hex([1, 171])).value()[1] == 171, "round trip");

    # Percent-escapes for one path segment or query value, and form data.
    assert(Uri.encode("a b&c") == "a%20b%26c", "escaped");
    var query = Uri.encode_form([("q", "pepper lang"), ("page", "2")]);
    assert(query == "q=pepper+lang&page=2", "form-encoded");
    var pairs = Uri.decode_form(query).value();
    assert(pairs[0].1 == "pepper lang", "decoded");

    # UUIDs: random (v4) and time-ordered (v7).
    var id = uuid.Uuid.v4();
    assert(uuid.Uuid.parse(id.to_string()).value() == id, "round trip");
    assert(uuid.Uuid.v7().version() == 7, "time-ordered");
    return 0;
}
