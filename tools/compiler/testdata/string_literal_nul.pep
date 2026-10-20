# Two literals, one the other's part before a NUL: each keeps its own bytes
# (#53).
main(): int {
    var prefix = "a";
    var whole = "a\0b";
    print($"{prefix.size} {prefix.byte_at(0)}");
    print($"{whole.size} {whole.byte_at(0)} {whole.byte_at(1)} {whole.byte_at(2)}");
    return 0;
}
