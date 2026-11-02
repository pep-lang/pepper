# `ordered = true` derives `compare` from the fields `==` compares.
[Equatable(ordered = true)]
struct Version {
    var major: int;
    var minor: int;
    # Left out of `==`, the hash and the order.
    [Equatable(exclude = true)]
    var label: String;

    construct(this.major = 0, this.minor = 0, this.label = "") {}
}

main(): int {
    assert(Version(1, 2) < Version(1, 10), "by major, then minor");
    assert(Version(2, 0, "beta") == Version(2, 0, "final"), "the label takes no part");
    var versions = [Version(1, 10), Version(0, 9), Version(1, 2)];
    versions.sort();
    assert(versions[0].major == 0 && versions[2].minor == 10, "sorted");
    return 0;
}
