import os;

main(): int {
    # Measure with the monotonic clock: subtracting two instants gives a
    # Duration.
    var start = os.Instant.now();
    var total = 0;
    for (var i in 0..100000) {
        total = total + i;
    }
    var elapsed = os.Instant.now() - start;
    print($"summed in {elapsed}");   # such as "1.234ms"

    var timeout = os.Duration.from_seconds(2) + os.Duration.from_milliseconds(500);
    assert(timeout.milliseconds() == 2500, "whole milliseconds");
    assert(timeout.to_string() == "2.5s", "the largest unit it reaches");
    assert(elapsed < timeout, "durations compare");

    # The wall clock counts from the Unix epoch.
    var now = os.SystemTime.now();
    assert(now.unix_seconds() > 1700000000, "after November 2023");
    var tomorrow = now + os.Duration.from_seconds(86400);
    assert(tomorrow.duration_since(now).value() == os.Duration.from_seconds(86400), "a day later");
    assert(now.duration_since(tomorrow).is_none(), "no negative durations");
    return 0;
}
