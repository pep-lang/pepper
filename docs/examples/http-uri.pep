main(): int {
    # Any scheme parses; the scheme is lowercased and nothing else changes.
    var uri = Uri.parse("HTTPS://user@example.com:8443/caf%C3%A9?page=2#top").value();
    assert(uri.scheme == "https" && uri.host.value() == "example.com", "scheme and host");
    assert(uri.port.value() == 8443 && uri.user_info.value() == "user", "port and user information");
    assert(uri.path == "/caf%C3%A9" && uri.query.value() == "page=2", "path and query keep their escapes");
    assert(Uri.decode(uri.path).value() == "/café", "decoded path");
    assert(uri.path_and_query() == "/caf%C3%A9?page=2", "what an HTTP request line names");

    # Missing parts are Empty: a mailto URI has no authority.
    var mail = Uri.parse("mailto:someone@example.com").value();
    assert(mail.host.is_empty() && mail.path == "someone@example.com", "no authority");

    # A relative reference has no scheme, like a request target on a server.
    var target = Uri.parse("/items?page=2").value();
    assert(!target.is_absolute() && target.path == "/items", "relative");

    assert(Uri.parse("http://example.com/a b").is_err(), "a space must be percent-encoded");
    return 0;
}
