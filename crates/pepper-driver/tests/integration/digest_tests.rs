//! The `digest` module (runtime/digest/): SHA-256, SHA-1 and BLAKE3 against
//! published test vectors and digests from reference implementations
//! (Python's `hashlib` and the `blake3` package), one-shot and incremental
//! in uneven pieces, with no allocation left behind.

use crate::support::jit_census;

fn run(source: &str) -> i32 {
    let (result, leaked) = jit_census(source);
    assert_eq!(leaked, 0, "allocations leaked or double-released");
    result
}

/// A program that checks the digests of `size` bytes `index % 251` for each
/// `(size, sha256, sha1, blake3)` row, one-shot and fed 37 bytes at a time.
fn check_rows(rows: &[(u64, &str, &str, &str)]) -> String {
    let mut checks = String::new();
    for (i, (size, sha256, sha1, blake3)) in rows.iter().enumerate() {
        let code = (i as i32 + 1) * 10;
        checks.push_str(&format!(
            "    if (!check({size}, \"{sha256}\", \"{sha1}\", \"{blake3}\")) {{ return -{code}; }}\n"
        ));
    }
    format!(
        r##"
import digest;

pattern(size: ulong): u8[] {{
    var data = Array<u8>(size);
    ulong index = 0;
    while (index < size) {{
        data.append((index % 251) as u8);
        index += 1;
    }}
    return data;
}}

check(size: ulong, sha256: String, sha1: String, blake3: String): bool {{
    var data = pattern(size);
    if (digest.to_hex(digest.sha256(data)) != sha256) {{ return false; }}
    if (digest.to_hex(digest.sha1(data)) != sha1) {{ return false; }}
    if (digest.to_hex(digest.blake3(data)) != blake3) {{ return false; }}
    var a = digest.Sha256();
    var b = digest.Sha1();
    var c = digest.Blake3();
    ulong at = 0;
    while (at < size) {{
        ulong count = 37;
        if (count > size - at) {{ count = size - at; }}
        var part = Array<u8>(count);
        ulong k = 0;
        while (k < count) {{
            part.append(data[at + k]);
            k += 1;
        }}
        a.update(part);
        b.update(part);
        c.update(part);
        at += count;
    }}
    return a.finish_hex() == sha256 and b.finish_hex() == sha1 and c.finish_hex() == blake3;
}}

test(): int {{
{checks}    return 0;
}}
"##
    )
}

#[test]
fn digests_match_reference_implementations() {
    // Sizes around the 64-byte block, the 56-byte padding limit, and
    // BLAKE3's 1024-byte chunks and the subtree merges after 2, 3 and 4
    // chunks and more.
    let rows = [
        (0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "da39a3ee5e6b4b0d3255bfef95601890afd80709", "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"),
        (1, "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d", "5ba93c9db0cff93f52b521d7420e43f6eda2784f", "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213"),
        (55, "463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59", "8ae2d46729cfe68ff927af5eec9c7d1b66d65ac2", "d04ec5f6f5e7daf5ced7a1671fbe912580a56576c8bf6a2ed4b80e35548f9c13"),
        (56, "da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562", "636e2ec698dac903498e648bd2f3af641d3c88cb", "60f238116f2936698a88cda03d8df79d7431249373b048ee7a063849fe6e9742"),
        (63, "29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488", "6d942da0c4392b123528f2905c713a3ce28364bd", "e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b"),
        (64, "fdeab9acf3710362bd2658cdc9a29e8f9c757fcf9811603a8c447cd1d9151108", "c6138d514ffa2135bfce0ed0b8fac65669917ec7", "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98"),
        (65, "4bfd2c8b6f1eec7a2afeb48b934ee4b2694182027e6d0fc075074f2fabb31781", "69bd728ad6e13cd76ff19751fde427b00e395746", "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee"),
        (119, "da18797ed7c3a777f0847f429724a2d8cd5138e6ed2895c3fa1a6d39d18f7ec6", "41c89d06001bab4ab78736b44efe7ce18ce6ae08", "82878aa8005c85f2b3e847da4b825891409a00d2950aafe87d39bf07f8fa1077"),
        (120, "f52b23db1fbb6ded89ef42a23ce0c8922c45f25c50b568a93bf1c075420bbb7c", "d3dbd653bd8597b7475321b60a36891278e6a04a", "1c5f22834ad113cfbca3cfdb2884327061dbc873924ab2a35c8ee470594f074b"),
        (1023, "1c5e88a585b61754df6137d66632a7348557a88358afc401b0a0a4fc427104a9", "1d58257e7e9cecee00473911023732e408e9bee3", "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11"),
        (1024, "2bce1ba628720664be4b9fdd77aae0678e5f0f3f02fc6ff641ec879094f6a404", "0ac28084ff74933d05123496dafd3791684d9b53", "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"),
        (1025, "bc0b6b10b89b9487a12fda2a8cc13194e7091c217aabf8b92846274026f4bcd0", "ca9fdc040579afc74c0e6314fee7af12bd5c4284", "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444"),
        (2048, "b2a8170614e23194ae2951423d601987f518ce2f11205d7b0b708080103b9f76", "b473a1c7d3ec7fa9036b3158a979dc0c65ab6d98", "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a"),
        (2049, "26e1e2808e3a6cf967ca03f6749a063c5ed55f92f5874653a1faabed78346f00", "08f4013d7a63d68a95db3d9ac6d6e29e932f2808", "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030"),
        (3072, "5f24b2f16026ec7d0450a5a08283d3cfd47302fe859f579ed79fe7d2663b73f9", "75cfc01b8d827c264b86ab897a6c731e2902f69e", "b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd2"),
        (4096, "d67c656e01756650d77717b0839985a056ec28ffe174601d690fc407a2ceffca", "92ca8f2b4163e64a1b53e0fde263ad56cbdb75fc", "015094013f57a5277b59d8475c0501042c0b642e531b0a1c8f58d2163229e969"),
        (5121, "f19db61046ca889db9bd34d779cd362c6a7198cb5a0e3a2882e7bd24a901cc1d", "b8af1be942099162396c64018eaca2dfdf685ebb", "628bd2cb2004694adaab7bbd778a25df25c47b9d4155a55f8fbd79f2fe154cff"),
        (8193, "7e3691790cd64b19d4edb1a80e988214515abeb53aa0f34ffbfe4b4bf405d120", "c7fac2a2751ad1552813f366c3daef8eba512436", "bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b"),
    ];
    assert_eq!(run(&check_rows(&rows)), 0);
}

#[test]
fn strings_and_published_vectors() {
    // FIPS 180-4 and the BLAKE3 reference, for text input.
    let source = r##"
import digest;

test(): int {
    if (digest.to_hex(digest.sha256("abc")) != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") { return -1; }
    var long_text = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    if (digest.to_hex(digest.sha256(long_text)) != "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1") { return -2; }
    if (digest.to_hex(digest.sha1("abc")) != "a9993e364706816aba3e25717850c26c9cd0d89d") { return -3; }
    if (digest.to_hex(digest.sha1(long_text)) != "84983e441c3bd26ebaae4aa1f95129e5e54670f1") { return -4; }
    if (digest.to_hex(digest.blake3("abc")) != "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85") { return -5; }
    # A String and its bytes hash the same.
    if (digest.to_hex(digest.blake3("héllo")) != digest.to_hex(digest.blake3("héllo".bytes()))) { return -6; }
    # `finish` resets the hasher.
    var hasher = digest.Sha256();
    hasher.update("discarded");
    hasher.finish();
    hasher.update("abc");
    if (hasher.finish_hex() != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") { return -7; }
    var b3 = digest.Blake3();
    b3.update("discarded");
    b3.reset();
    if (b3.finish_hex() != "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262") { return -8; }
    # A git blob id: "blob <size>" and a NUL, then the content.
    var git = digest.Sha1();
    u8[] nul = [0];
    git.update("blob 6");
    git.update(nul);
    git.update("hello\n");
    if (git.finish_hex() != "ce013625030ba8dba906f756967f9e9ca394464a") { return -9; }
    if (digest.to_hex([0, 1, 127, 128, 255]) != "00017f80ff") { return -10; }
    if (digest.sha256(Array<u8>()).count != 32 or digest.sha1(Array<u8>()).count != 20) { return -11; }
    return 0;
}
"##;
    assert_eq!(run(source), 0);
}
