# Random numbers: this thread's generator, a seeded one, and secure bytes.
import random;

main(): int {
    # This thread's generator, seeded from the operating system.
    var die = random.next_int(1..>6);
    assert(die >= 1 && die <= 6, "a die roll");
    var names = ["ada", "grace", "edsger"];
    random.shuffle(names);
    var pick = random.choose(names);
    assert(names.contains(pick), "one of the names");

    # A seeded generator gives the same numbers on every run and platform.
    var a = random.Generator(2024);
    var b = random.Generator(2024);
    assert(a.next_double() == b.next_double(), "same seed, same numbers");

    # Keys and tokens come from the operating system, not a generator.
    var key = random.bytes(32);
    assert(key.count == 32, "256 bits");
    return 0;
}
