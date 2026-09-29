import "counter" as c;
import [increment_size as size] from "counter";

main(): int {
    var k: c.Counter = c.Counter();
    k.increment();
    k.increment();
    return k.count - 2 * size();
}
