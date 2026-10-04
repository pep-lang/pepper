# IP and socket addresses: parsing, the RFC 5952 text form, construction,
# equality and predicates, and resolving a literal host. Pure Pepper, the
# same on every platform.

import io;

ip(text: String): String {
    var r = io.IpAddress.parse(text);
    assert(r.is_ok(), "parses: " + text);
    return r.value().to_string();
}

expect_bad_ip(text: String) {
    var r = io.IpAddress.parse(text);
    assert(r.is_err(), "rejects: " + text);
    assert(r.error().is_invalid_input(), "invalid input: " + text);
}

socket_text(text: String): String {
    var r = io.SocketAddress.parse(text);
    assert(r.is_ok(), "parses: " + text);
    return r.value().to_string();
}

expect_bad_socket(text: String) {
    var r = io.SocketAddress.parse(text);
    assert(r.is_err(), "rejects: " + text);
    assert(r.error().is_invalid_input(), "invalid input: " + text);
}

[Test]
ipv4_parses_and_formats() {
    expect_equal(ip("0.0.0.0"), "0.0.0.0");
    expect_equal(ip("255.255.255.255"), "255.255.255.255");
    expect_equal(ip("192.168.1.10"), "192.168.1.10");
    expect_bad_ip("");
    expect_bad_ip("256.1.1.1");
    expect_bad_ip("1.2.3");
    expect_bad_ip("1.2.3.4.5");
    expect_bad_ip("01.2.3.4");
    expect_bad_ip("1..2.3");
    expect_bad_ip("1.2.3.");
    expect_bad_ip(" 1.2.3.4");
    expect_bad_ip("1.2.3.4 ");
    expect_bad_ip("a.b.c.d");
    expect_bad_ip("1.2.3.-4");
    expect_bad_ip("1234.1.1.1");
}

[Test]
ipv6_parses_and_formats_in_rfc_5952_form() {
    expect_equal(ip("::"), "::");
    expect_equal(ip("::1"), "::1");
    expect_equal(ip("1::"), "1::");
    expect_equal(ip("0:0:0:0:0:0:0:1"), "::1");
    expect_equal(ip("2001:DB8:0:0:8:800:200C:417A"), "2001:db8::8:800:200c:417a");
    expect_equal(ip("ff01:0:0:0:0:0:0:101"), "ff01::101");
    expect_equal(ip("1:0:0:2:0:0:0:3"), "1:0:0:2::3");       # the longest run wins
    expect_equal(ip("1:0:0:2:0:0:3:4"), "1::2:0:0:3:4");     # the first of equal runs wins
    expect_equal(ip("1:0:3:4:5:6:7:8"), "1:0:3:4:5:6:7:8");  # one zero stays
    expect_equal(ip("0001:0002:0003:0004:0005:0006:0007:0008"), "1:2:3:4:5:6:7:8");
    expect_equal(ip("1:2:3:4:5:6:7::"), "1:2:3:4:5:6:7:0");
    expect_equal(ip("::ffff:192.0.2.1"), "::ffff:192.0.2.1");
    expect_equal(ip("64:ff9b::192.0.2.33"), "64:ff9b::c000:221");
    expect_bad_ip(":::");
    expect_bad_ip("1:::2");
    expect_bad_ip("1::2::3");
    expect_bad_ip("1:2:3:4:5:6:7:8:9");
    expect_bad_ip("1:2:3:4:5:6:7");
    expect_bad_ip("1:2:3:4:5:6:7:8::");
    expect_bad_ip("12345::");
    expect_bad_ip("g::");
    expect_bad_ip(":1");
    expect_bad_ip("1:");
    expect_bad_ip("::1.2.3");
    expect_bad_ip("1:2:3:4:5:6:7:1.2.3.4");
    expect_bad_ip("[::1]");
    expect_bad_ip("fe80::1%eth0");
}

[Test]
ip_construction_equality_and_predicates() {
    var a = io.IpAddress.v4(10, 0, 0, 1);
    expect_true(a == io.IpAddress.parse("10.0.0.1").value());
    expect_true(a != io.IpAddress.v4(10, 0, 0, 2));
    expect_true(a.is_v4());
    expect_false(a.is_v6());
    expect_equal(io.IpAddress.v6(8193, 3512, 0, 0, 0, 0, 0, 1).to_string(), "2001:db8::1");
    expect_true(io.IpAddress.parse("::ffff:10.0.0.1").value() != a);  # mapped v6 is not v4
    expect_true(io.IpAddress.loopback_v4().is_loopback());
    expect_true(io.IpAddress.v4(127, 255, 0, 9).is_loopback());
    expect_true(io.IpAddress.loopback_v6().is_loopback());
    expect_false(a.is_loopback());
    expect_true(io.IpAddress().is_unspecified());
    expect_true(io.IpAddress().is_v4());
    expect_true(io.IpAddress.unspecified_v6().is_unspecified());
    var bytes = a.to_bytes();
    expect_equal(bytes.count, 4);
    expect_equal(bytes[0], 10);
    expect_equal(bytes[3], 1);
    var bytes6 = io.IpAddress.loopback_v6().to_bytes();
    expect_equal(bytes6.count, 16);
    expect_equal(bytes6[0], 0);
    expect_equal(bytes6[15], 1);
}

[Test]
socket_addresses_parse_and_format() {
    expect_equal(socket_text("1.2.3.4:0"), "1.2.3.4:0");
    expect_equal(socket_text("1.2.3.4:65535"), "1.2.3.4:65535");
    expect_equal(socket_text("[::1]:8080"), "[::1]:8080");
    expect_equal(socket_text("[2001:DB8::1]:443"), "[2001:db8::1]:443");
    expect_bad_socket("");
    expect_bad_socket("1.2.3.4");
    expect_bad_socket("1.2.3.4:");
    expect_bad_socket("1.2.3.4:65536");
    expect_bad_socket("1.2.3.4:123456");
    expect_bad_socket("1.2.3.4:8a");
    expect_bad_socket("::1:80");
    expect_bad_socket("[::1]");
    expect_bad_socket("[::1]:");
    expect_bad_socket("[::1]80");
    expect_bad_socket("[1.2.3.4]:80");
    expect_bad_socket("[::1:80");
    var s = io.SocketAddress(io.IpAddress.loopback_v4(), 8080);
    expect_equal(s.port(), 8080);
    expect_true(s.address() == io.IpAddress.loopback_v4());
    expect_true(s == io.SocketAddress.parse("127.0.0.1:8080").value());
    expect_true(s != io.SocketAddress(io.IpAddress.loopback_v4(), 8081));
    expect_equal(io.SocketAddress().to_string(), "0.0.0.0:0");
    expect_true(io.SocketAddress.parse("[::1]:1").value().is_v6());
}

[Test]
a_literal_host_resolves_to_itself() {
    var literal = io.resolve("192.0.2.7", 99).value();
    expect_equal(literal.count, 1);
    expect_equal(literal[0].to_string(), "192.0.2.7:99");
    expect_equal(io.resolve("::1", 7).value()[0].to_string(), "[::1]:7");
    expect_true(io.resolve("", 80).error().is_invalid_input());
}
