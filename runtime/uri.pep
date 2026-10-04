## URI references (RFC 3986): parse any URI, such as `https://example.com/a?b#c`,
## `mailto:someone@example.com` or `/items?page=2`, into its parts.

import "internals";

## A URI reference split into its RFC 3986 components: scheme, authority
## (user information, host and port), path, query and fragment.
##
## `Uri.parse` accepts any scheme, and a reference with no scheme (a
## relative reference, such as `/items?page=2`, which is what an HTTP
## server sees as a request's target). The components keep their
## percent-escapes as written; `Uri.decode` turns an escaped component into
## text. The scheme is lowercased, since schemes are case-insensitive;
## nothing else is changed. `to_string()` puts the parts back together.
##
## A component that can be absent is optional, so an empty one (`http://h/?`
## has an empty query) differs from a missing one (`http://h/` has none).
##
## @example
##     var uri = Uri.parse("HTTPS://user@example.com:8443/a%20b?x=1#top").value();
##     assert(uri.scheme == "https", "the scheme is lowercased");
##     assert(uri.user_info.value() == "user", "user information");
##     assert(uri.host.value() == "example.com", "host");
##     assert(uri.port.value() == 8443, "port");
##     assert(uri.path == "/a%20b", "the path keeps its escapes");
##     assert(Uri.decode(uri.path).value() == "/a b", "decoded");
##     assert(uri.query.value() == "x=1" && uri.fragment.value() == "top", "query and fragment");
export struct Uri {
    ## The scheme, lowercased, such as `https`; empty for a relative reference.
    var scheme: String;
    ## The user information before `@` in the authority, if any.
    var user_info: String?;
    ## The host, without the brackets of an IPv6 address; Empty when the URI
    ## has no authority (no `//`), and empty for one such as `file:///tmp`.
    ## An IPv6 scope keeps its escaped `%` (RFC 6874): the host of
    ## `http://[fe80::1%25eth0]/` is `fe80::1%25eth0`, which `Uri.decode`
    ## turns into the `fe80::1%eth0` that `io.IpAddress.parse` reads.
    var host: String?;
    ## The port after the host, if the authority gives one.
    var port: u16?;
    ## The path, possibly empty, with its percent-escapes.
    var path: String;
    ## The query after `?`, without the `?`, if any.
    var query: String?;
    ## The fragment after `#`, without the `#`, if any.
    var fragment: String?;

    ## Creates an empty relative reference: no scheme, no authority, and an
    ## empty path.
    construct() {
        this.scheme = "";
        this.path = "";
    }

    ## Parses `text` as a URI reference: an absolute URI with any scheme,
    ## or a relative reference.
    ##
    ## Characters outside printable ASCII (spaces, controls, and every
    ## non-ASCII byte) must be percent-encoded, and each `%` must be
    ## followed by two hexadecimal digits.
    ##
    ## @param text the URI reference
    ## @returns the parsed URI, or an error saying what is wrong: an invalid
    ##   scheme, a character that must be encoded, a bad escape, an IPv6 host
    ##   with no `]`, or a port that is not a number from 0 to 65535
    ## @example
    ##     var mail = Uri.parse("mailto:someone@example.com").value();
    ##     assert(mail.scheme == "mailto" && mail.host.is_empty(), "no authority");
    ##     assert(mail.path == "someone@example.com", "the path holds the address");
    ##     assert(Uri.parse("a b").is_err(), "a space must be encoded");
    static parse(text: String): Result<Uri> {
        var data = text.bytes();
        var size = data.count;
        ulong index = 0;
        while (index < size) {
            var c = data[index] as int;
            if (c <= ' ' || c >= 127) {
                return _uri_invalid(text, $"character {index} must be percent-encoded");
            }
            if (c == '%') {
                if (index + 2 >= size) {
                    return _uri_invalid(text, "'%' is not followed by two hexadecimal digits");
                }
                if (_pep_hex_digit(data[index + 1]) < 0 || _pep_hex_digit(data[index + 2]) < 0) {
                    return _uri_invalid(text, "'%' is not followed by two hexadecimal digits");
                }
            }
            index = index + 1;
        }

        var uri = Uri();
        ulong start = 0;
        # The scheme is the text before the first ':' that comes before any
        # '/', '?' or '#'.
        index = 0;
        while (index < size && !_uri_ends_segment(data[index]) && data[index] != ':') {
            index = index + 1;
        }
        if (index < size && data[index] == ':') {
            var scheme = text.substr_bytes(0, index);
            if (!_uri_is_scheme(scheme)) {
                return _uri_invalid(text, $"invalid scheme '{scheme}'");
            }
            uri.scheme = scheme.lower();
            start = index + 1;
        }

        # The authority follows "//" and runs to the next '/', '?' or '#'.
        if (start + 1 < size && data[start] == '/' && data[start + 1] == '/') {
            start = start + 2;
            var end = start;
            while (end < size && !_uri_ends_segment(data[end])) {
                end = end + 1;
            }
            var authority = text.substr_bytes(start, end - start);
            var failure = _uri_parse_authority(uri, authority);
            if (failure.size > 0) {
                return _uri_invalid(text, failure);
            }
            start = end;
        }

        # The path runs to '?' or '#', the query from '?' to '#'.
        var end = start;
        while (end < size && data[end] != '?' && data[end] != '#') {
            end = end + 1;
        }
        uri.path = text.substr_bytes(start, end - start);
        if (end < size && data[end] == '?') {
            start = end + 1;
            end = start;
            while (end < size && data[end] != '#') {
                end = end + 1;
            }
            uri.query = Optional<String>.Value(text.substr_bytes(start, end - start));
        }
        if (end < size) {
            start = end + 1;
            uri.fragment = Optional<String>.Value(text.substr_bytes(start, size - start));
        }
        return Result<Uri>.ok(uri);
    }

    ## Returns `text` with each percent-escape (`%20`) replaced by the byte
    ## it stands for, decoded as UTF-8. A `+` is kept as it is; a query that
    ## uses `+` for a space needs that replaced first.
    ##
    ## @param text a component with percent-escapes, such as `path`
    ## @returns the decoded text, where each byte sequence that is not valid
    ##   UTF-8 becomes U+FFFD, the replacement character, or an error when a
    ##   `%` is not followed by two hexadecimal digits
    ## @example
    ##     assert(Uri.decode("caf%C3%A9%21").value() == "café!", "decoded");
    ##     assert(Uri.decode("100%").is_err(), "a lone '%'");
    static decode(text: String): Result<String> {
        var data = text.bytes();
        var size = data.count;
        var decoded = Array<u8>(size);
        ulong index = 0;
        while (index < size) {
            var c = data[index];
            if (c == '%') {
                if (index + 2 >= size) {
                    return Result<String>.err(Error($"invalid percent-escape in '{text}'"));
                }
                var high = _pep_hex_digit(data[index + 1]);
                var low = _pep_hex_digit(data[index + 2]);
                if (high < 0 || low < 0) {
                    return Result<String>.err(Error($"invalid percent-escape in '{text}'"));
                }
                decoded.append((high * 16 + low) as u8);
                index = index + 3;
            } else {
                decoded.append(c);
                index = index + 1;
            }
        }
        return Result<String>.ok(String._from_bytes(decoded));
    }

    ## Returns whether this URI has a scheme (an absolute URI rather than a
    ## relative reference).
    ##
    ## @returns true when `scheme` is not empty
    is_absolute(): bool {
        return scheme.size > 0;
    }

    ## Returns the authority as it appears after `//`: user information,
    ## host (in brackets when it is an IPv6 address) and port.
    ##
    ## @returns the authority, such as `user@example.com:8443`, or Empty when
    ##   `host` is Empty
    authority(): String? {
        if (host.is_empty()) {
            return Optional<String>.Empty;
        }
        var text = StringBuilder();
        if (user_info.is_value()) {
            text.append(user_info.value());
            text.append("@");
        }
        var name = host.value();
        if (name.contains(":")) {
            text.append($"[{name}]");
        } else {
            text.append(name);
        }
        if (port.is_value()) {
            var number = port.value();
            text.append($":{number}");
        }
        return Optional<String>.Value(text.to_string());
    }

    ## Returns the path and query, as an HTTP request line names its target:
    ## the path (`/` when it is empty), then `?` and the query if there is
    ## one. The fragment is left out.
    ##
    ## @returns the path and query, such as `/items?page=2`
    path_and_query(): String {
        var text = path.size == 0 ? "/" : path;
        if (query.is_value()) {
            return $"{text}?{query.value()}";
        }
        return text;
    }

    ## Resolves `reference` against this URI, its base, as RFC 3986
    ## (section 5.2) describes and as a browser resolves a link on a page:
    ## an absolute `reference` stands as it is, `//host/path` keeps only the
    ## base's scheme, `/path` keeps its authority too, and a relative path
    ## replaces the base's last segment. `.` and `..` segments are removed.
    ## The fragment is always the reference's.
    ##
    ## @param reference the reference to resolve, such as an HTTP `Location`
    ## @returns the resolved URI
    ## @example
    ##     var base = Uri.parse("https://example.com/docs/guide/intro?x=1").value();
    ##     assert(base.resolve(Uri.parse("next").value()).to_string() == "https://example.com/docs/guide/next", "a sibling");
    ##     assert(base.resolve(Uri.parse("../api").value()).to_string() == "https://example.com/docs/api", "up one");
    ##     assert(base.resolve(Uri.parse("/").value()).to_string() == "https://example.com/", "the root");
    ##     assert(base.resolve(Uri.parse("?y=2").value()).to_string() == "https://example.com/docs/guide/intro?y=2", "a new query");
    resolve(reference: Uri): Uri {
        var target = Uri();
        if (reference.scheme.size > 0) {
            target.scheme = reference.scheme;
            target._take_authority(reference);
            target.path = _uri_remove_dots(reference.path);
            target.query = reference.query;
        } else {
            if (reference.host.is_value()) {
                target._take_authority(reference);
                target.path = _uri_remove_dots(reference.path);
                target.query = reference.query;
            } else {
                if (reference.path.size == 0) {
                    target.path = path;
                    target.query = reference.query.is_value() ? reference.query : query;
                } else {
                    if (reference.path.starts_with("/")) {
                        target.path = _uri_remove_dots(reference.path);
                    } else {
                        target.path = _uri_remove_dots(_merge(reference.path));
                    }
                    target.query = reference.query;
                }
                target._take_authority(this);
            }
            target.scheme = scheme;
        }
        target.fragment = reference.fragment;
        return target;
    }

    # Copies the user information, host and port of `other`.
    _take_authority(other: Uri) {
        user_info = other.user_info;
        host = other.host;
        port = other.port;
    }

    # `relative` in place of this path's last segment (RFC 3986 5.2.3).
    _merge(relative: String): String {
        if (host.is_value() && path.size == 0) {
            return "/" + relative;
        }
        var slash = path.rfind("/");
        if (slash < 0) {
            return relative;
        }
        return path.substr_bytes(0, slash as ulong + 1) + relative;
    }

    ## Returns the URI as text, putting its components back together. For a
    ## parsed URI this is the text it was parsed from, except that the
    ## scheme is lowercased.
    ##
    ## @returns the URI reference as a String
    to_string(): String {
        var text = StringBuilder();
        if (scheme.size > 0) {
            text.append(scheme);
            text.append(":");
        }
        var named = authority();
        if (named.is_value()) {
            text.append("//");
            text.append(named.value());
        }
        text.append(path);
        if (query.is_value()) {
            text.append("?");
            text.append(query.value());
        }
        if (fragment.is_value()) {
            text.append("#");
            text.append(fragment.value());
        }
        return text.to_string();
    }
}

extend Uri with ToString;

# `path` without its `.` and `..` segments (RFC 3986 5.2.4).
_uri_remove_dots(path: String): String {
    var input = path;
    var output = "";
    while (input.size > 0) {
        if (input.starts_with("../")) {
            input = input.substr_bytes(3, input.size - 3);
        } else if (input.starts_with("./")) {
            input = input.substr_bytes(2, input.size - 2);
        } else if (input.starts_with("/./")) {
            input = input.substr_bytes(2, input.size - 2);
        } else if (input == "/.") {
            input = "/";
        } else if (input.starts_with("/../")) {
            input = input.substr_bytes(3, input.size - 3);
            output = _uri_drop_last_segment(output);
        } else if (input == "/..") {
            input = "/";
            output = _uri_drop_last_segment(output);
        } else if (input == "." || input == "..") {
            input = "";
        } else {
            # Move the first segment, with its leading `/`, to the output.
            var next = input.find("/", 1);
            if (next < 0) {
                output = output + input;
                input = "";
            } else {
                output = output + input.substr_bytes(0, next as ulong);
                input = input.substr_bytes(next as ulong, input.size - next as ulong);
            }
        }
    }
    return output;
}

# `output` without its last segment and the `/` before it.
_uri_drop_last_segment(output: String): String {
    var slash = output.rfind("/");
    if (slash < 0) {
        return "";
    }
    return output.substr_bytes(0, slash as ulong);
}

_uri_invalid(text: String, why: String): Result<Uri> {
    return Result<Uri>.err(Error($"invalid URI '{text}': {why}"));
}

# Whether `c` ends the scheme or the authority: '/', '?' or '#'.
_uri_ends_segment(c: u8): bool {
    return c == '/' || c == '?' || c == '#';
}

# Whether `text` is a scheme: a letter, then letters, digits, '+', '-' or '.'.
_uri_is_scheme(text: String): bool {
    ulong index = 0;
    while (index < text.size) {
        var c = text.byte_at(index) as int;
        var letter = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
        var other = (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.';
        if (!letter && (index == 0 || !other)) {
            return false;
        }
        index = index + 1;
    }
    return text.size > 0;
}

# Fills `uri`'s user information, host and port from `authority`, and
# returns what is wrong with it, or an empty string.
_uri_parse_authority(uri: Uri, authority: String): String {
    var rest = authority;
    var at = rest.find("@");
    if (at >= 0) {
        uri.user_info = Optional<String>.Value(rest.substr_bytes(0, at as ulong));
        rest = rest.substr_bytes(at as ulong + 1, rest.size - at as ulong - 1);
    }
    var port_text = "";
    var has_port = false;
    if (rest.starts_with("[")) {
        var close = rest.find("]");
        if (close < 0) {
            return "no ']' after an IPv6 address";
        }
        uri.host = Optional<String>.Value(rest.substr_bytes(1, close as ulong - 1));
        var after = rest.substr_bytes(close as ulong + 1, rest.size - close as ulong - 1);
        if (after.size > 0) {
            if (!after.starts_with(":")) {
                return "unexpected text after the IPv6 address";
            }
            has_port = true;
            port_text = after.substr_bytes(1, after.size - 1);
        }
    } else {
        var colon = rest.find(":");
        if (colon >= 0) {
            has_port = true;
            port_text = rest.substr_bytes(colon as ulong + 1, rest.size - colon as ulong - 1);
            rest = rest.substr_bytes(0, colon as ulong);
        }
        uri.host = Optional<String>.Value(rest);
    }
    # An empty port ("host:") is allowed and means none.
    if (has_port && port_text.size > 0) {
        if (port_text.size > 5) {
            return $"invalid port '{port_text}'";
        }
        long port = 0;
        ulong index = 0;
        while (index < port_text.size) {
            var c = port_text.byte_at(index) as int;
            if (c < '0' || c > '9') {
                return $"invalid port '{port_text}'";
            }
            port = port * 10 + (c - '0');
            index = index + 1;
        }
        if (port > 65535) {
            return $"invalid port '{port_text}'";
        }
        uri.port = Optional<u16>.Value(port as u16);
    }
    return "";
}
