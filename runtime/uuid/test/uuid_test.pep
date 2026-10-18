# The uuid module: parsing and formatting, the version and variant bits of
# v4 and v7, and v7's time order.

import os;
import uuid;

[Test]
parses_and_formats() {
    var id = uuid.Uuid.parse("0190163D-8694-739b-AEA5-966c26f8ad91").value();
    expect_equal(id.high, 0x0190163d8694739b);
    expect_equal(id.low, 0xaea5966c26f8ad91);
    expect_equal(id.to_string(), "0190163d-8694-739b-aea5-966c26f8ad91");
    expect_equal($"{id}", "0190163d-8694-739b-aea5-966c26f8ad91");
    expect_equal(id.version(), 7);
    var bytes = id.bytes();
    expect_equal(bytes.count, 16 as ulong);
    expect_equal(bytes[0], 0x01 as u8);
    expect_equal(bytes[8], 0xae as u8);
    expect_equal(bytes[15], 0x91 as u8);
    expect_equal(uuid.Uuid(0, 0).to_string(), "00000000-0000-0000-0000-000000000000");
    expect_true(uuid.Uuid.parse("0190163d-8694-739b-aea5-966c26f8ad91").value() == id);
}

[Test]
rejects_other_forms() {
    var bad = [
        "",
        "0190163d8694739baea5966c26f8ad91",
        "{0190163d-8694-739b-aea5-966c26f8ad91}",
        "0190163d-8694-739b-aea5-966c26f8ad9",
        "0190163d-8694-739b-aea5-966c26f8ad9g",
        "0190163d+8694-739b-aea5-966c26f8ad91",
        "0190163-d8694-739b-aea5-966c26f8ad91",
    ];
    for (var text in bad) {
        expect_true(uuid.Uuid.parse(text).is_err());
    }
}

[Test]
v4_is_random_with_version_and_variant() {
    var a = uuid.Uuid.v4();
    var b = uuid.Uuid.v4();
    expect_true(a != b);
    expect_equal(a.version(), 4);
    expect_equal(a.low >> 62, 2 as ulong);
    expect_equal(a.to_string().byte_at(14), '4' as byte);
    expect_true(uuid.Uuid.parse(a.to_string()).value() == a);
}

[Test]
v7_starts_with_the_time() {
    var before = os.SystemTime.now().unix_milliseconds() as ulong;
    var id = uuid.Uuid.v7();
    var after = os.SystemTime.now().unix_milliseconds() as ulong;
    expect_equal(id.version(), 7);
    expect_equal(id.low >> 62, 2 as ulong);
    var milliseconds = id.high >> 16;
    expect_true(milliseconds >= before && milliseconds <= after);
}
