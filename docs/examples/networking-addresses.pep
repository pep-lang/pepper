import io;

main(): int {
    var home = io.IpAddress.v4(127, 0, 0, 1);
    assert(home.is_loopback(), "127.0.0.1 is loopback");

    # Text is read strictly and printed in one canonical form.
    var six = io.IpAddress.parse("2001:DB8:0:0:0:0:0:1").value();
    assert(six.to_string() == "2001:db8::1", "IPv6 prints compressed and lowercase");
    assert(io.IpAddress.parse("256.1.1.1").error().is_invalid_input(), "256 is out of range");

    var service = io.SocketAddress.parse("[::1]:8080").value();
    assert(service.is_v6() && service.port() == 8080, "IPv6 with a port");
    assert(service.to_string() == "[::1]:8080", "brackets around IPv6");

    # A host name goes to the system resolver; an IP address is used as is.
    var local = io.resolve("localhost", 80).value();
    assert(local.count() >= 1 && local[0].address().is_loopback(), "localhost is loopback");
    return 0;
}
