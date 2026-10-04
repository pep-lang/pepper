# Compress small messages against a preset dictionary of what they share.
import compress;

main(): int {
    # Short messages with the same keys compress poorly on their own: the
    # stream has no earlier bytes to refer back to.
    var dictionary = "{\"user\": \"\", \"action\": \"login\", \"status\": \"ok\"}".bytes();
    var message = "{\"user\": \"ada\", \"action\": \"login\", \"status\": \"ok\"}".bytes();

    var plain = compress.Zlib.compress(message);
    var primed = compress.Zlib.compress(message, dictionary);
    assert(primed.count < plain.count, "the dictionary supplies the repeated text");

    # Decompressing needs the same dictionary; the stream names it by its
    # Adler-32, so a missing or different one is an error.
    assert(compress.Zlib.decompress(primed, dictionary).value() == message, "round trip");
    assert(compress.Zlib.decompress(primed).is_err(), "no dictionary given");
    print($"{plain.count} bytes alone, {primed.count} with the dictionary");
    return 0;
}
