# Cryptographic hashes: one-shot, incremental, and as hexadecimal text.
import digest;

main(): int {
    # One call hashes a whole input, bytes or a String's UTF-8 bytes.
    var id = digest.to_hex(digest.sha256("hello"));
    assert(id == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", "SHA-256");

    # A hasher takes the input in pieces, such as the blocks of a file as
    # they are read; the digest does not depend on how it was split.
    var hasher = digest.Blake3();
    hasher.update("hel");
    hasher.update("lo");
    var whole = digest.blake3("hello");
    assert(hasher.finish() == whole, "same digest");
    assert(whole.count == 32, "32 bytes");

    # git names a file's content by the SHA-1 of a header and the bytes.
    u8[] nul = [0];
    var git = digest.Sha1();
    git.update("blob 6");
    git.update(nul);
    git.update("hello\n");
    assert(git.finish_hex() == "ce013625030ba8dba906f756967f9e9ca394464a", "git blob id");
    return 0;
}
