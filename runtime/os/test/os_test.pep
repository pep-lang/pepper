# os: Duration arithmetic and text, the monotonic and wall clocks, and what
# the module reports about the machine and the user. os_tests.rs keeps the
# checks that need a variable the parent sets or the host's own name.

import io;
import os;

[Test]
duration_arithmetic_comparison_and_text() {
    var a = os.Duration.from_seconds(2) + os.Duration.from_milliseconds(500);
    expect_equal(a.milliseconds(), 2500);
    expect_equal(a.seconds(), 2);
    expect_equal(a.microseconds(), 2500000);
    expect_equal(a.nanoseconds(), 2500000000);
    expect_equal(a, os.Duration.from_microseconds(2500000));
    expect_true(a == os.Duration.from_nanoseconds(2500000000));
    expect_true(os.Duration.from_seconds(1) < a);
    expect_true(a <= a);
    expect_true(a > os.Duration());
    expect_true(a >= a);
    var b = a - os.Duration.from_milliseconds(1500);
    expect_equal(b, os.Duration.from_seconds(1));
    expect_equal(b * 3, os.Duration.from_seconds(3));
    expect_equal(b / 4, os.Duration.from_milliseconds(250));
    expect_true(os.Duration().is_zero());
    expect_false(b.is_zero());
    expect_equal(a.seconds_fraction(), 2.5);
    expect_equal(a.to_string(), "2.5s");
    expect_equal(os.Duration.from_milliseconds(15).to_string(), "15ms");
    expect_equal(os.Duration.from_nanoseconds(1250).to_string(), "1.25µs");
    expect_equal(os.Duration.from_nanoseconds(40).to_string(), "40ns");
    expect_equal(os.Duration().to_string(), "0s");
    expect_equal($"{os.Duration.from_nanoseconds(1000000001)}", "1.000000001s");
}

[Test]
instants_measure_forward() {
    var start = os.Instant.now();
    var later = os.Instant.now();
    var elapsed = later - start;
    os.Duration typed = elapsed;
    expect_false(later < start);
    expect_true(start <= later);
    var moved = start + os.Duration.from_seconds(5);
    expect_equal(moved - start, os.Duration.from_seconds(5));
    expect_true(moved - os.Duration.from_seconds(5) == start);
    expect_true(moved > later);
    expect_true(start.elapsed() >= elapsed);
}

[Test]
system_time_counts_from_the_unix_epoch() {
    var now = os.SystemTime.now();
    # 2023-11-14 and 2200-01-01.
    expect_true(now.unix_seconds() >= 1700000000);
    expect_true(now.unix_seconds() <= 7258118400);
    var epoch = os.SystemTime();
    expect_equal(epoch.unix_nanoseconds(), 0);
    expect_true(now.duration_since(epoch).is_value());
    expect_false(epoch.duration_since(now).is_value());
    var before = os.SystemTime.from_unix_nanoseconds(-1);
    expect_equal(before.unix_seconds(), -1);
    expect_equal(before.unix_milliseconds(), -1);
    var ten = os.SystemTime.from_unix_seconds(10);
    expect_equal(ten.duration_since(epoch).value(), os.Duration.from_seconds(10));
    expect_true(ten - os.Duration.from_seconds(10) == epoch);
    expect_true(epoch + os.Duration.from_seconds(10) == ten);
    expect_true(epoch < ten);
    expect_equal(ten.unix_milliseconds(), 10000);
    expect_true(ten.elapsed().is_value());
}

[Test]
machine_and_user() {
    expect_false(os.hostname().is_empty);
    expect_true(os.logical_cpus() >= 1);
    expect_true(os.physical_cpus() >= 1);
    expect_true(os.physical_cpus() <= os.logical_cpus());
    expect_true(os.total_memory() >= 16777216);
    var page = os.page_size();
    expect_true(page >= 4096);
    expect_equal(page & (page - 1), 0);
    expect_false(os.system_version().is_empty);
    expect_false(os.user_name().is_empty());
    expect_false(os.home_directory().is_empty());
    expect_equal(os.temp_directory().to_string(), io.Directory.temp().to_string());
}
