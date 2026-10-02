# Prefetching: start loading memory a loop will soon read.
import hint;

main(): int {
    var text = "a long text that a loop will read";
    hint.prefetch_read(text.c_str());
    var spaces = 0;
    for (var index in 0..text.length) {
        if (text.byte_at(index) == ' ') {
            spaces += 1;
        }
    }
    assert(spaces == 7, "a hint changes nothing the program computes");
    return 0;
}
