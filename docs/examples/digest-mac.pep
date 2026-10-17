# Message authentication: HMAC, BLAKE3's keyed mode and key derivation.
import digest;

main(): int {
    # A webhook signs its body with HMAC-SHA-256 under a shared secret;
    # the receiver computes the MAC again and compares in constant time.
    var body = "{\"event\":\"push\"}";
    var received = digest.hmac_sha256("webhook secret", body);
    var signature = "493db758cb288b3801a0084bcdd27bd565ca0fb9b0a149404d2b4442c9d79bcd";
    assert(digest.to_hex(received) == signature, "HMAC-SHA-256");
    var expected = digest.Hmac<digest.Sha256>("webhook secret");
    expected.update(body);
    assert(digest.equal_constant_time(expected.finish(), received), "authentic");

    # Derive a 32-byte key for one purpose from a shared secret, then use
    # it for BLAKE3's keyed mode.
    var derive = digest.Blake3.derive_key("example.com 2026-10-16 webhook MACs v1");
    derive.update("a shared secret");
    var mac = digest.Blake3.keyed(derive.finish());
    mac.update(body);
    assert(mac.finish().count == 32, "a 32-byte MAC");

    # BLAKE3 gives output of any length; the first 32 bytes are the digest.
    var hasher = digest.Blake3();
    hasher.update(body);
    var long_output = hasher.finish(64);
    assert(long_output.count == 64, "64 bytes");
    assert(digest.to_hex(long_output).starts_with(digest.to_hex(digest.blake3(body))), "a prefix");
    return 0;
}
