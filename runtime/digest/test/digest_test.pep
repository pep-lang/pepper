# The digest module: SHA-256, SHA-1 and BLAKE3, HMAC, PBKDF2, and BLAKE3's
# keyed hashing, key derivation and extended output, against published test
# vectors (RFC 4231, RFC 2202, RFC 7914, the BLAKE3 team's test_vectors.json) and
# digests from reference implementations (Python's hashlib and the blake3
# package), one-shot and incremental in uneven pieces. They run
# twice: with the portable code, and built with `-D USE_LIBCRYPTO`
# (libcrypto, or CNG on Windows).

import digest;
import random;

# `size` bytes, each `index % 251`.
pattern(size: ulong): u8[] {
    var data = Array<u8>(size);
    ulong index = 0;
    while (index < size) {
        data.append((index % 251) as u8);
        index += 1;
    }
    return data;
}

# Checks the digests of `pattern(size)`, one-shot and fed 37 bytes at a time.
check(size: ulong, sha256: String, sha1: String, blake3: String) {
    var data = pattern(size);
    expect_equal(digest.to_hex(digest.sha256(data)), sha256);
    expect_equal(digest.to_hex(digest.sha1(data)), sha1);
    expect_equal(digest.to_hex(digest.blake3(data)), blake3);
    var a = digest.Sha256();
    var b = digest.Sha1();
    var c = digest.Blake3();
    ulong at = 0;
    while (at < size) {
        ulong count = 37;
        if (count > size - at) {
            count = size - at;
        }
        var part = Array<u8>(count);
        ulong k = 0;
        while (k < count) {
            part.append(data[at + k]);
            k += 1;
        }
        a.update(part);
        b.update(part);
        c.update(part);
        at += count;
    }
    expect_equal(a.finish_hex(), sha256);
    expect_equal(b.finish_hex(), sha1);
    expect_equal(c.finish_hex(), blake3);
}

# Sizes around the 64-byte block, the 56-byte padding limit, and BLAKE3's
# 1024-byte chunks and the subtree merges after 2, 3 and 4 chunks and more.
[Test]
digests_match_reference_implementations() {
    check(
        0,
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "da39a3ee5e6b4b0d3255bfef95601890afd80709",
        "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
    );
    check(
        1,
        "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d",
        "5ba93c9db0cff93f52b521d7420e43f6eda2784f",
        "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213"
    );
    check(
        55,
        "463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59",
        "8ae2d46729cfe68ff927af5eec9c7d1b66d65ac2",
        "d04ec5f6f5e7daf5ced7a1671fbe912580a56576c8bf6a2ed4b80e35548f9c13"
    );
    check(
        56,
        "da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562",
        "636e2ec698dac903498e648bd2f3af641d3c88cb",
        "60f238116f2936698a88cda03d8df79d7431249373b048ee7a063849fe6e9742"
    );
    check(
        63,
        "29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488",
        "6d942da0c4392b123528f2905c713a3ce28364bd",
        "e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b"
    );
    check(
        64,
        "fdeab9acf3710362bd2658cdc9a29e8f9c757fcf9811603a8c447cd1d9151108",
        "c6138d514ffa2135bfce0ed0b8fac65669917ec7",
        "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98"
    );
    check(
        65,
        "4bfd2c8b6f1eec7a2afeb48b934ee4b2694182027e6d0fc075074f2fabb31781",
        "69bd728ad6e13cd76ff19751fde427b00e395746",
        "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee"
    );
    check(
        119,
        "da18797ed7c3a777f0847f429724a2d8cd5138e6ed2895c3fa1a6d39d18f7ec6",
        "41c89d06001bab4ab78736b44efe7ce18ce6ae08",
        "82878aa8005c85f2b3e847da4b825891409a00d2950aafe87d39bf07f8fa1077"
    );
    check(
        120,
        "f52b23db1fbb6ded89ef42a23ce0c8922c45f25c50b568a93bf1c075420bbb7c",
        "d3dbd653bd8597b7475321b60a36891278e6a04a",
        "1c5f22834ad113cfbca3cfdb2884327061dbc873924ab2a35c8ee470594f074b"
    );
    check(
        1023,
        "1c5e88a585b61754df6137d66632a7348557a88358afc401b0a0a4fc427104a9",
        "1d58257e7e9cecee00473911023732e408e9bee3",
        "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11"
    );
    check(
        1024,
        "2bce1ba628720664be4b9fdd77aae0678e5f0f3f02fc6ff641ec879094f6a404",
        "0ac28084ff74933d05123496dafd3791684d9b53",
        "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"
    );
    check(
        1025,
        "bc0b6b10b89b9487a12fda2a8cc13194e7091c217aabf8b92846274026f4bcd0",
        "ca9fdc040579afc74c0e6314fee7af12bd5c4284",
        "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444"
    );
    check(
        2048,
        "b2a8170614e23194ae2951423d601987f518ce2f11205d7b0b708080103b9f76",
        "b473a1c7d3ec7fa9036b3158a979dc0c65ab6d98",
        "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a"
    );
    check(
        2049,
        "26e1e2808e3a6cf967ca03f6749a063c5ed55f92f5874653a1faabed78346f00",
        "08f4013d7a63d68a95db3d9ac6d6e29e932f2808",
        "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030"
    );
    check(
        3072,
        "5f24b2f16026ec7d0450a5a08283d3cfd47302fe859f579ed79fe7d2663b73f9",
        "75cfc01b8d827c264b86ab897a6c731e2902f69e",
        "b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd2"
    );
    check(
        4096,
        "d67c656e01756650d77717b0839985a056ec28ffe174601d690fc407a2ceffca",
        "92ca8f2b4163e64a1b53e0fde263ad56cbdb75fc",
        "015094013f57a5277b59d8475c0501042c0b642e531b0a1c8f58d2163229e969"
    );
    check(
        5121,
        "f19db61046ca889db9bd34d779cd362c6a7198cb5a0e3a2882e7bd24a901cc1d",
        "b8af1be942099162396c64018eaca2dfdf685ebb",
        "628bd2cb2004694adaab7bbd778a25df25c47b9d4155a55f8fbd79f2fe154cff"
    );
    check(
        8193,
        "7e3691790cd64b19d4edb1a80e988214515abeb53aa0f34ffbfe4b4bf405d120",
        "c7fac2a2751ad1552813f366c3daef8eba512436",
        "bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b"
    );
}

# FIPS 180-4 and the BLAKE3 reference, for text input.
[Test]
strings_and_published_vectors() {
    expect_equal(
        digest.to_hex(digest.sha256("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
    var long_text = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    expect_equal(
        digest.to_hex(digest.sha256(long_text)), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    );
    expect_equal(digest.to_hex(digest.sha1("abc")), "a9993e364706816aba3e25717850c26c9cd0d89d");
    expect_equal(digest.to_hex(digest.sha1(long_text)), "84983e441c3bd26ebaae4aa1f95129e5e54670f1");
    expect_equal(
        digest.to_hex(digest.blake3("abc")), "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85"
    );
    # A String and its bytes hash the same.
    expect_equal(digest.to_hex(digest.blake3("héllo")), digest.to_hex(digest.blake3("héllo".bytes())));
    # `finish` resets the hasher.
    var hasher = digest.Sha256();
    hasher.update("discarded");
    hasher.finish();
    hasher.update("abc");
    expect_equal(hasher.finish_hex(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    var blake3_hasher = digest.Blake3();
    blake3_hasher.update("discarded");
    blake3_hasher.reset();
    expect_equal(blake3_hasher.finish_hex(), "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262");
    # A git blob id: "blob <size>" and a NUL, then the content.
    var git = digest.Sha1();
    u8[] nul = [0];
    git.update("blob 6");
    git.update(nul);
    git.update("hello\n");
    expect_equal(git.finish_hex(), "ce013625030ba8dba906f756967f9e9ca394464a");
    expect_equal(digest.to_hex([0, 1, 127, 128, 255]), "00017f80ff");
    expect_equal(digest.sha256(Array<u8>()).count, 32);
    expect_equal(digest.sha1(Array<u8>()).count, 20);
}

# `count` copies of `byte`.
repeated(byte: u8, count: ulong): u8[] {
    var bytes = Array<u8>(count);
    ulong index = 0;
    while (index < count) {
        bytes.append(byte);
        index += 1;
    }
    return bytes;
}

# The bytes 1, 2, ... 25: the key of the fourth RFC test case.
counting_key(): u8[] {
    var bytes = Array<u8>(25);
    ulong index = 1;
    while (index <= 25) {
        bytes.append(index as u8);
        index += 1;
    }
    return bytes;
}

# Checks `mac` (hex) as the one-shot functions and the incremental `Hmac`,
# fed one byte at a time, compute it; a truncated MAC is a prefix.
check_hmac(key: u8[], message: u8[], sha256: String, sha1: String) {
    expect_true(digest.to_hex(digest.hmac_sha256(key, message)).starts_with(sha256));
    expect_true(digest.to_hex(digest.hmac_sha1(key, message)).starts_with(sha1));
    var mac256 = digest.Hmac<digest.Sha256>(key);
    var mac1 = digest.Hmac<digest.Sha1>(key);
    for (var value in message) {
        u8[] one = [value];
        mac256.update(one);
        mac1.update(one);
    }
    expect_true(mac256.finish_hex().starts_with(sha256));
    expect_true(mac1.finish_hex().starts_with(sha1));
}

[Test]
hmac_matches_rfc_4231_and_rfc_2202() {
    var long_key = repeated(0xaa, 131);
    var long_message = "This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.";
    check_hmac(
        repeated(0x0b, 20),
        "Hi There".bytes(),
        "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
        "b617318655057264e28bc0b6fb378c8ef146be00"
    );
    check_hmac(
        "Jefe".bytes(),
        "what do ya want for nothing?".bytes(),
        "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
        "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79"
    );
    check_hmac(
        repeated(0xaa, 20),
        repeated(0xdd, 50),
        "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe",
        "125d7342b9ac11cd91a39af48aa17b4f63f175d3"
    );
    check_hmac(
        counting_key(),
        repeated(0xcd, 50),
        "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b",
        "4c9007f4026250c6bc8414f9bf50c86c2d7235da"
    );
    check_hmac(
        repeated(0x0c, 20),
        "Test With Truncation".bytes(),
        "a3b6167473100ee06e0c796c2955552b",
        "4c1a03424b55e07fe7f27be1"
    );
    check_hmac(
        long_key,
        "Test Using Larger Than Block-Size Key - Hash Key First".bytes(),
        "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
        "90d0dace1c1bdc957339307803160335bde6df2b"
    );
    check_hmac(
        long_key,
        long_message.bytes(),
        "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2",
        "217e44bb08b6e06a2d6c30f3cb9f537f97c63356"
    );
    expect_equal(
        digest.to_hex(
            digest.hmac_sha1(repeated(0xaa, 80), "Test Using Larger Than Block-Size Key - Hash Key First".bytes())
        ),
        "aa4ae5e15272d00e95705637ce8a3b55ed402112"
    );
    expect_equal(
        digest.to_hex(
            digest.hmac_sha1(
                repeated(0xaa, 80), "Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data".bytes()
            )
        ),
        "e8e99d0f45237d786d6bbaa7965c7808bbff1a91"
    );
    # A String key and message are their UTF-8 bytes.
    expect_equal(
        digest.to_hex(digest.hmac_sha256("Jefe", "what do ya want for nothing?")),
        "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
    );
    expect_equal(
        digest.to_hex(digest.hmac_sha1("Jefe", "what do ya want for nothing?")),
        "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79"
    );
    # `finish` and `reset` keep the key.
    var mac = digest.Hmac<digest.Sha256>("Jefe");
    mac.update("discarded");
    mac.reset();
    mac.update("what do ya want ");
    mac.update("for nothing?");
    var first = mac.finish();
    mac.update("what do ya want for nothing?");
    expect_true(digest.equal_constant_time(first, mac.finish()));
}

[Test]
pbkdf2_sha256_matches_rfc_7914() {
    expect_equal(
        digest.to_hex(digest.pbkdf2_sha256("passwd".bytes(), "salt".bytes(), 1, 64)),
        "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783"
    );
    expect_equal(
        digest.to_hex(digest.pbkdf2_sha256("Password", "NaCl".bytes(), 80000, 64)),
        "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d"
    );
    # A password over a block (hashed first), an empty salt, and a length
    # that ends partway through a third block, against Python's hashlib.
    expect_equal(
        digest.to_hex(digest.pbkdf2_sha256(pattern(100), Array<u8>(), 3, 70)),
        "bbbba2a6dead65a0684a7fd433196aea23fbc9cf73496ad93a63ef2689feb8ef4f25eeaf527fd48d4290560dcbd3a3590408d088b8af98bb9f29c69a7d98ad6a351e2312b9f2"
    );
    expect_equal(digest.pbkdf2_sha256("passwd", "salt".bytes(), 1, 0).count, 0 as ulong);
}

# PBKDF2-HMAC-SHA256 from one-shot HMACs, as RFC 8018 states it, to check
# the copied pad states of `digest.pbkdf2_sha256` against.
pbkdf2_by_hmac(password: u8[], salt: u8[], rounds: ulong, length: ulong): u8[] {
    var key = Array<u8>(length);
    uint index = 1;
    while (key.count < length) {
        var message = Array<u8>();
        message.append_all(salt);
        message.append((index >> 24) as u8);
        message.append((index >> 16) as u8);
        message.append((index >> 8) as u8);
        message.append(index as u8);
        var round = digest.hmac_sha256(password, message);
        var block = Array<u8>();
        block.append_all(round);
        ulong done = 1;
        while (done < rounds) {
            round = digest.hmac_sha256(password, round);
            ulong byte = 0;
            while (byte < 32) {
                block[byte] = block[byte] ^ round[byte];
                byte += 1;
            }
            done += 1;
        }
        ulong take = 0;
        while (take < 32 && key.count < length) {
            key.append(block[take]);
            take += 1;
        }
        index += 1;
    }
    return key;
}

[Test]
pbkdf2_sha256_matches_per_round_hmac_for_random_inputs() {
    var generator = random.Generator(148);
    ulong trial = 0;
    while (trial < 40) {
        # Passwords and salts up to two blocks long: a password over a
        # block is hashed first, and a salt may span blocks.
        var password = Array<u8>();
        var password_size = generator.next_ulong() % 140;
        while (password.count < password_size) {
            password.append(generator.next_ulong() as u8);
        }
        var salt = Array<u8>();
        var salt_size = generator.next_ulong() % 140;
        while (salt.count < salt_size) {
            salt.append(generator.next_ulong() as u8);
        }
        var rounds = 1 + generator.next_ulong() % 20;
        var length = 1 + generator.next_ulong() % 100;
        expect_equal(
            digest.to_hex(digest.pbkdf2_sha256(password, salt, rounds, length)),
            digest.to_hex(pbkdf2_by_hmac(password, salt, rounds, length))
        );
        trial += 1;
    }
}

[Test]
[ShouldPanic("pbkdf2_sha256: 'rounds' must be at least 1")]
pbkdf2_sha256_with_no_rounds_panics() {
    digest.pbkdf2_sha256("passwd", "salt".bytes(), 0, 32);
}

[Test]
[ShouldPanic("pbkdf2_sha256: 'length' is over RFC 8018's limit")]
pbkdf2_sha256_past_rfc_8018s_limit_panics() {
    digest.pbkdf2_sha256("passwd", "salt".bytes(), 1, 0xffffffff * 32 + 1);
}

[Test]
equal_constant_time_compares_bytes() {
    u8[] a = [1, 2, 3];
    u8[] b = [1, 2, 3];
    u8[] c = [1, 2, 4];
    u8[] d = [1, 2];
    expect_true(digest.equal_constant_time(a, b));
    expect_true(!digest.equal_constant_time(a, c));
    expect_true(!digest.equal_constant_time(a, d));
    expect_true(digest.equal_constant_time(Array<u8>(), Array<u8>()));
}

# Checks the three modes' 131-byte output for `pattern(size)`, fed in one
# piece and 37 bytes at a time, and that the default 32 bytes are its prefix.
check_blake3(size: ulong, hash: String, keyed_hash: String, derive_key: String) {
    var key = "whats the Elvish word for friend".bytes();
    var context = "BLAKE3 2019-12-27 16:29:52 test vectors context";
    var data = pattern(size);
    var hashers = [digest.Blake3(), digest.Blake3.keyed(key), digest.Blake3.derive_key(context)];
    var expected = [hash, keyed_hash, derive_key];
    ulong mode = 0;
    while (mode < 3) {
        var hasher = hashers[mode];
        hasher.update(data);
        expect_equal(digest.to_hex(hasher.finish(131)), expected[mode]);
        ulong at = 0;
        while (at < size) {
            hasher.update_range(data, at, 37);
            at += 37;
        }
        expect_equal(hasher.finish_hex(), expected[mode].substr(0, 64));
        mode += 1;
    }
}

# Sizes around a block, a chunk, and the subtree merges after 2, 3 and 4
# chunks and more.
[Test]
blake3_modes_match_official_vectors() {
    check_blake3(
        0,
        "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262e00f03e7b69af26b7faaf09fcd333050338ddfe085b8cc869ca98b206c08243a26f5487789e8f660afe6c99ef9e0c52b92e7393024a80459cf91f476f9ffdbda7001c22e159b402631f277ca96f2defdf1078282314e763699a31c5363165421cce14d",
        "92b2b75604ed3c761f9d6f62392c8a9227ad0ea3f09573e783f1498a4ed60d26b18171a2f22a4b94822c701f107153dba24918c4bae4d2945c20ece13387627d3b73cbf97b797d5e59948c7ef788f54372df45e45e4293c7dc18c1d41144a9758be58960856be1eabbe22c2653190de560ca3b2ac4aa692a9210694254c371e851bc8f",
        "2cc39783c223154fea8dfb7c1b1660f2ac2dcbd1c1de8277b0b0dd39b7e50d7d905630c8be290dfcf3e6842f13bddd573c098c3f17361f1f206b8cad9d088aa4a3f746752c6b0ce6a83b0da81d59649257cdf8eb3e9f7d4998e41021fac119deefb896224ac99f860011f73609e6e0e4540f93b273e56547dfd3aa1a035ba6689d89a0"
    );
    check_blake3(
        1,
        "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213c3a6cb8bf623e20cdb535f8d1a5ffb86342d9c0b64aca3bce1d31f60adfa137b358ad4d79f97b47c3d5e79f179df87a3b9776ef8325f8329886ba42f07fb138bb502f4081cbcec3195c5871e6c23e2cc97d3c69a613eba131e5f1351f3f1da786545e5",
        "6d7878dfff2f485635d39013278ae14f1454b8c0a3a2d34bc1ab38228a80c95b6568c0490609413006fbd428eb3fd14e7756d90f73a4725fad147f7bf70fd61c4e0cf7074885e92b0e3f125978b4154986d4fb202a3f331a3fb6cf349a3a70e49990f98fe4289761c8602c4e6ab1138d31d3b62218078b2f3ba9a88e1d08d0dd4cea11",
        "b3e2e340a117a499c6cf2398a19ee0d29cca2bb7404c73063382693bf66cb06c5827b91bf889b6b97c5477f535361caefca0b5d8c4746441c57617111933158950670f9aa8a05d791daae10ac683cbef8faf897c84e6114a59d2173c3f417023a35d6983f2c7dfa57e7fc559ad751dbfb9ffab39c2ef8c4aafebc9ae973a64f0c76551"
    );
    check_blake3(
        63,
        "e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b1197012b1e7d9af4d7cb7bdd1f3bb49a90a9b5dec3ea2bbc6eaebce77f4e470cbf4687093b5352f04e4a4570fba233164e6acc36900e35d185886a827f7ea9bdc1e5c3ce88b095a200e62c10c043b3e9bc6cb9b6ac4dfa51794b02ace9f98779040755",
        "bb1eb5d4afa793c1ebdd9fb08def6c36d10096986ae0cfe148cd101170ce37aea05a63d74a840aecd514f654f080e51ac50fd617d22610d91780fe6b07a26b0847abb38291058c97474ef6ddd190d30fc318185c09ca1589d2024f0a6f16d45f11678377483fa5c005b2a107cb9943e5da634e7046855eaa888663de55d6471371d55d",
        "b6451e30b953c206e34644c6803724e9d2725e0893039cfc49584f991f451af3b89e8ff572d3da4f4022199b9563b9d70ebb616efff0763e9abec71b550f1371e233319c4c4e74da936ba8e5bbb29a598e007a0bbfa929c99738ca2cc098d59134d11ff300c39f82e2fce9f7f0fa266459503f64ab9913befc65fddc474f6dc1c67669"
    );
    check_blake3(
        64,
        "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98fc9cc56cb831ffe33ea8e7e1d1df09b26efd2767670066aa82d023b1dfe8ab1b2b7fbb5b97592d46ffe3e05a6a9b592e2949c74160e4674301bc3f97e04903f8c6cf95b863174c33228924cdef7ae47559b10b294acd660666c4538833582b43f82d74",
        "ba8ced36f327700d213f120b1a207a3b8c04330528586f414d09f2f7d9ccb7e68244c26010afc3f762615bbac552a1ca909e67c83e2fd5478cf46b9e811efccc93f77a21b17a152ebaca1695733fdb086e23cd0eb48c41c034d52523fc21236e5d8c9255306e48d52ba40b4dac24256460d56573d1312319afcf3ed39d72d0bfc69acb",
        "a5c4a7053fa86b64746d4bb688d06ad1f02a18fce9afd3e818fefaa7126bf73e9b9493a9befebe0bf0c9509fb3105cfa0e262cde141aa8e3f2c2f77890bb64a4cca96922a21ead111f6338ad5244f2c15c44cb595443ac2ac294231e31be4a4307d0a91e874d36fc9852aeb1265c09b6e0cda7c37ef686fbbcab97e8ff66718be048bb"
    );
    check_blake3(
        65,
        "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee0e16e0a4749d6811dd1d6d1265c29729b1b75a9ac346cf93f0e1d7296dfcfd4313b3a227faaaaf7757cc95b4e87a49be3b8a270a12020233509b1c3632b3485eef309d0abc4a4a696c9decc6e90454b53b000f456a3f10079072baaf7a981653221f2c",
        "c0a4edefa2d2accb9277c371ac12fcdbb52988a86edc54f0716e1591b4326e72d5e795f46a596b02d3d4bfb43abad1e5d19211152722ec1f20fef2cd413e3c22f2fc5da3d73041275be6ede3517b3b9f0fc67ade5956a672b8b75d96cb43294b9041497de92637ed3f2439225e683910cb3ae923374449ca788fb0f9bea92731bc26ad",
        "51fd05c3c1cfbc8ed67d139ad76f5cf8236cd2acd26627a30c104dfd9d3ff8a82b02e8bd36d8498a75ad8c8e9b15eb386970283d6dd42c8ae7911cc592887fdbe26a0a5f0bf821cd92986c60b2502c9be3f98a9c133a7e8045ea867e0828c7252e739321f7c2d65daee4468eb4429efae469a42763f1f94977435d10dccae3e3dce88d"
    );
    check_blake3(
        1023,
        "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11a182d27a591b05592b15607500e1e8dd56bc6c7fc063715b7a1d737df5bad3339c56778957d870eb9717b57ea3d9fb68d1b55127bba6a906a4a24bbd5acb2d123a37b28f9e9a81bbaae360d58f85e5fc9d75f7c370a0cc09b6522d9c8d822f2f28f485",
        "c951ecdf03288d0fcc96ee3413563d8a6d3589547f2c2fb36d9786470f1b9d6e890316d2e6d8b8c25b0a5b2180f94fb1a158ef508c3cde45e2966bd796a696d3e13efd86259d756387d9becf5c8bf1ce2192b87025152907b6d8cc33d17826d8b7b9bc97e38c3c85108ef09f013e01c229c20a83d9e8efac5b37470da28575fd755a10",
        "74a16c1c3d44368a86e1ca6df64be6a2f64cce8f09220787450722d85725dea59c413264404661e9e4d955409dfe4ad3aa487871bcd454ed12abfe2c2b1eb7757588cf6cb18d2eccad49e018c0d0fec323bec82bf1644c6325717d13ea712e6840d3e6e730d35553f59eff5377a9c350bcc1556694b924b858f329c44ee64b884ef00d"
    );
    check_blake3(
        1024,
        "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af71cf8107265ecdaf8505b95d8fcec83a98a6a96ea5109d2c179c47a387ffbb404756f6eeae7883b446b70ebb144527c2075ab8ab204c0086bb22b7c93d465efc57f8d917f0b385c6df265e77003b85102967486ed57db5c5ca170ba441427ed9afa684e",
        "75c46f6f3d9eb4f55ecaaee480db732e6c2105546f1e675003687c31719c7ba4a78bc838c72852d4f49c864acb7adafe2478e824afe51c8919d06168414c265f298a8094b1ad813a9b8614acabac321f24ce61c5a5346eb519520d38ecc43e89b5000236df0597243e4d2493fd626730e2ba17ac4d8824d09d1a4a8f57b8227778e2de",
        "7356cd7720d5b66b6d0697eb3177d9f8d73a4a5c5e968896eb6a6896843027066c23b601d3ddfb391e90d5c8eccdef4ae2a264bce9e612ba15e2bc9d654af1481b2e75dbabe615974f1070bba84d56853265a34330b4766f8e75edd1f4a1650476c10802f22b64bd3919d246ba20a17558bc51c199efdec67e80a227251808d8ce5bad"
    );
    check_blake3(
        1025,
        "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444f4c4a22b4b399155358a994e52bf255de60035742ec71bd08ac275a1b51cc6bfe332b0ef84b409108cda080e6269ed4b3e2c3f7d722aa4cdc98d16deb554e5627be8f955c98e1d5f9565a9194cad0c4285f93700062d9595adb992ae68ff12800ab67a",
        "357dc55de0c7e382c900fd6e320acc04146be01db6a8ce7210b7189bd664ea69362396b77fdc0d2634a552970843722066c3c15902ae5097e00ff53f1e116f1cd5352720113a837ab2452cafbde4d54085d9cf5d21ca613071551b25d52e69d6c81123872b6f19cd3bc1333edf0c52b94de23ba772cf82636cff4542540a7738d5b930",
        "effaa245f065fbf82ac186839a249707c3bddf6d3fdda22d1b95a3c970379bcb5d31013a167509e9066273ab6e2123bc835b408b067d88f96addb550d96b6852dad38e320b9d940f86db74d398c770f462118b35d2724efa13da97194491d96dd37c3c09cbef665953f2ee85ec83d88b88d11547a6f911c8217cca46defa2751e7f3ad"
    );
    check_blake3(
        2048,
        "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a9a60bf80001410ec9eea6698cd537939fad4749edd484cb541aced55cd9bf54764d063f23f6f1e32e12958ba5cfeb1bf618ad094266d4fc3c968c2088f677454c288c67ba0dba337b9d91c7e1ba586dc9a5bc2d5e90c14f53a8863ac75655461cea8f9",
        "879cf1fa2ea0e79126cb1063617a05b6ad9d0b696d0d757cf053439f60a99dd10173b961cd574288194b23ece278c330fbb8585485e74967f31352a8183aa782b2b22f26cdcadb61eed1a5bc144b8198fbb0c13abbf8e3192c145d0a5c21633b0ef86054f42809df823389ee40811a5910dcbd1018af31c3b43aa55201ed4edaac74fe",
        "7b2945cb4fef70885cc5d78a87bf6f6207dd901ff239201351ffac04e1088a23e2c11a1ebffcea4d80447867b61badb1383d842d4e79645d48dd82ccba290769caa7af8eaa1bd78a2a5e6e94fbdab78d9c7b74e894879f6a515257ccf6f95056f4e25390f24f6b35ffbb74b766202569b1d797f2d4bd9d17524c720107f985f4ddc583"
    );
    check_blake3(
        2049,
        "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b687952256303096de31d71d74103403822a2e0bc1eb193e7aecc9643a76b7bbc0c9f9c52e8783aae98764ca468962b5c2ec92f0c74eb5448d519713e09413719431c802f948dd5d90425a4ecdadece9eb178d80f26efccae630734dff63340285adec2aed3b51073ad3",
        "9f29700902f7c86e514ddc4df1e3049f258b2472b6dd5267f61bf13983b78dd5f9a88abfefdfa1e00b418971f2b39c64ca621e8eb37fceac57fd0c8fc8e117d43b81447be22d5d8186f8f5919ba6bcc6846bd7d50726c06d245672c2ad4f61702c646499ee1173daa061ffe15bf45a631e2946d616a4c345822f1151284712f76b2b0e",
        "2ea477c5515cc3dd606512ee72bb3e0e758cfae7232826f35fb98ca1bcbdf27316d8e9e79081a80b046b60f6a263616f33ca464bd78d79fa18200d06c7fc9bffd808cc4755277a7d5e09da0f29ed150f6537ea9bed946227ff184cc66a72a5f8c1e4bd8b04e81cf40fe6dc4427ad5678311a61f4ffc39d195589bdbc670f63ae70f4b6"
    );
    check_blake3(
        3072,
        "b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd29a3f6b0b978d6608335c09dc94ccf682f9951cdfc501bfe47b9c9189a6fc7b404d120258506341a6d802857322fbd20d3e5dae05b95c88793fa83db1cb08e7d8008d1599b6209d78336e24839724c191b2a52a80448306e0daa84a3fdb566661a37e11",
        "044a0e7b172a312dc02a4c9a818c036ffa2776368d7f528268d2e6b5df19177022f302d0529e4174cc507c463671217975e81dab02b8fdeb0d7ccc7568dd22574c783a76be215441b32e91b9a904be8ea81f7a0afd14bad8ee7c8efc305ace5d3dd61b996febe8da4f56ca0919359a7533216e2999fc87ff7d8f176fbecb3d6f34278b",
        "050df97f8c2ead654d9bb3ab8c9178edcd902a32f8495949feadcc1e0480c46b3604131bbd6e3ba573b6dd682fa0a63e5b165d39fc43a625d00207607a2bfeb65ff1d29292152e26b298868e3b87be95d6458f6f2ce6118437b632415abe6ad522874bcd79e4030a5e7bad2efa90a7a7c67e93f0a18fb28369d0a9329ab5c24134ccb0"
    );
    check_blake3(
        4096,
        "015094013f57a5277b59d8475c0501042c0b642e531b0a1c8f58d2163229e9690289e9409ddb1b99768eafe1623da896faf7e1114bebeadc1be30829b6f8af707d85c298f4f0ff4d9438aef948335612ae921e76d411c3a9111df62d27eaf871959ae0062b5492a0feb98ef3ed4af277f5395172dbe5c311918ea0074ce0036454f620",
        "befc660aea2f1718884cd8deb9902811d332f4fc4a38cf7c7300d597a081bfc0bbb64a36edb564e01e4b4aaf3b060092a6b838bea44afebd2deb8298fa562b7b597c757b9df4c911c3ca462e2ac89e9a787357aaf74c3b56d5c07bc93ce899568a3eb17d9250c20f6c5f6c1e792ec9a2dcb715398d5a6ec6d5c54f586a00403a1af1de",
        "1e0d7f3db8c414c97c6307cbda6cd27ac3b030949da8e23be1a1a924ad2f25b9d78038f7b198596c6cc4a9ccf93223c08722d684f240ff6569075ed81591fd93f9fff1110b3a75bc67e426012e5588959cc5a4c192173a03c00731cf84544f65a2fb9378989f72e9694a6a394a8a30997c2e67f95a504e631cd2c5f55246024761b245"
    );
    check_blake3(
        5121,
        "628bd2cb2004694adaab7bbd778a25df25c47b9d4155a55f8fbd79f2fe154cff96adaab0613a6146cdaabe498c3a94e529d3fc1da2bd08edf54ed64d40dcd6777647eac51d8277d70219a9694334a68bc8f0f23e20b0ff70ada6f844542dfa32cd4204ca1846ef76d811cdb296f65e260227f477aa7aa008bac878f72257484f2b6c95",
        "6ccf1c34753e7a044db80798ecd0782a8f76f33563accaddbfbb2e0ea4b2d0240d07e63f13667a8d1490e5e04f13eb617aea16a8c8a5aaed1ef6fbde1b0515e3c81050b361af6ead126032998290b563e3caddeaebfab592e155f2e161fb7cba939092133f23f9e65245e58ec23457b78a2e8a125588aad6e07d7f11a85b88d375b72d",
        "b07f01e518e702f7ccb44a267e9e112d403a7b3f4883a47ffbed4b48339b3c341a0add0ac032ab5aaea1e4e5b004707ec5681ae0fcbe3796974c0b1cf31a194740c14519273eedaabec832e8a784b6e7cfc2c5952677e6c3f2c3914454082d7eb1ce1766ac7d75a4d3001fc89544dd46b5147382240d689bbbaefc359fb6ae30263165"
    );
    check_blake3(
        8193,
        "bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3bb2282aa69be089359ea1154b9a9286c4a56af4de975a9aa4a5c497654914d279bea60bb6d2cf7225a2fa0ff5ef56bbe4b149f3ed15860f78b4e2ad04e158e375c1e0c0b551cd7dfc82f1b155c11b6b3ed51ec9edb30d133653bb5709d1dbd55f4e1ff6",
        "954a2a75420c8d6547e3ba5b98d963e6fa6491addc8c023189cc519821b4a1f5f03228648fd983aef045c2fa8290934b0866b615f585149587dda2299039965328835a2b18f1d63b7e300fc76ff260b571839fe44876a4eae66cbac8c67694411ed7e09df51068a22c6e67d6d3dd2cca8ff12e3275384006c80f4db68023f24eebba57",
        "af1e0346e389b17c23200270a64aa4e1ead98c61695d917de7d5b00491c9b0f12f20a01d6d622edf3de026a4db4e4526225debb93c1237934d71c7340bb5916158cbdafe9ac3225476b6ab57a12357db3abbad7a26c6e66290e44034fb08a20a8d0ec264f309994d2810c49cfba6989d7abb095897459f5425adb48aba07c5fb3c83c0"
    );
    # A shorter output is a prefix of a longer one, and empty is allowed.
    var hasher = digest.Blake3();
    expect_equal(hasher.finish(0).count, 0);
    hasher.update("abc");
    expect_equal(digest.to_hex(hasher.finish(5)), "6437b3ac38");
}

[Test]
from_hex_reverses_to_hex() {
    var bytes = digest.from_hex("00ff7Fa0").value();
    expect_equal(bytes.count, 4 as ulong);
    expect_equal(bytes[1], 255 as u8);
    expect_equal(bytes[2], 0x7f as u8);
    expect_equal(digest.to_hex(bytes), "00ff7fa0");
    expect_equal(digest.from_hex("").value().count, 0 as ulong);
    expect_true(digest.from_hex("abc").is_err());
    expect_true(digest.from_hex("zz").is_err());
}
