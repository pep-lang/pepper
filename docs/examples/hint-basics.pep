# Optimizer hints: which way a branch usually goes, and memory a loop will
# soon read.
import hint;

main(): int {
    var values = [3, 1, 2];
    var total = 0;
    for (var value in values) {
        # Negative values are rare: keep the loop's fast path free of them.
        if (hint.unlikely(value < 0)) {
            return 1;
        }
        total += value;
    }
    assert(total == 6, "summed");

    var text = "a long text that a loop will read";
    hint.prefetch_read(text.c_str());
    assert(text.length > 0, "a hint changes nothing the program computes");
    return 0;
}
