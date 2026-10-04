## Network addresses: `IpAddress` (IPv4 or IPv6), `SocketAddress` (an IP
## address and a port), and `resolve`, which turns a host name into socket
## addresses.

# IpAddress keeps its 16 bytes in two ulongs, most significant byte first,
# so an address needs no allocation beyond the struct. Parsing and
# formatting are pure Pepper, so every platform accepts and prints exactly
# the same text.

import "socket_posix";
import "socket_wasi";
import "socket_windows";
import "sys_posix";
import "sys_windows";
import "types";

## An IPv4 or IPv6 address.
##
## Make one with `IpAddress.v4`, `IpAddress.v6`, `IpAddress.parse`, or one
## of the well-known addresses (`loopback_v4()`, `unspecified_v6()`, ...).
## `IpAddress()` is the IPv4 unspecified address `0.0.0.0`.
##
## `to_string()` prints IPv4 in dotted decimal (`127.0.0.1`) and IPv6 in the
## RFC 5952 form (`::1`, `2001:db8::8a2e:370:7334`); an IPv4-mapped IPv6
## address prints as `::ffff:1.2.3.4`. An IPv4 address and the IPv6 address
## that maps it are different values.
##
## An IPv6 address can carry a scope id, the network interface a link-local
## address such as `fe80::1` belongs to. Its text form is `fe80::1%eth0`
## (RFC 4007), and a socket address carries it to the system as
## `sin6_scope_id`.
##
## @example
##     import io;
##
##     var a = io.IpAddress.parse("192.168.1.10").value();
##     var b = io.IpAddress.v6(8193, 3512, 0, 0, 0, 0, 0, 1);   # 2001:db8::1
##     print(a.is_v4());         # true
##     print(b.to_string());     # 2001:db8::1
## @see SocketAddress
export struct IpAddress {
    ## Whether this is an IPv6 address.
    bool _is_v6;
    ## Bytes 0 to 7 of an IPv6 address, the first byte most significant; 0 for IPv4.
    ulong _high;
    ## Bytes 8 to 15 of an IPv6 address, or the IPv4 address in the low 32 bits.
    ulong _low;
    ## The IPv6 scope id (an interface index); 0 for none and for IPv4.
    uint _scope_id;

    ## Creates the IPv4 unspecified address, `0.0.0.0`.
    construct() {}

    ## Creates an IPv4 address from its four bytes, `a.b.c.d`.
    ##
    ## @param a the first byte
    ## @param b the second byte
    ## @param c the third byte
    ## @param d the fourth byte
    ## @returns the address `a.b.c.d`
    ## @example
    ##     var home = IpAddress.v4(127, 0, 0, 1);
    static v4(a: u8, b: u8, c: u8, d: u8): IpAddress {
        var address = IpAddress();
        address._low = ((a as ulong) << 24) | ((b as ulong) << 16) | ((c as ulong) << 8) | (d as ulong);
        return address;
    }

    ## Creates an IPv6 address from its eight 16-bit groups, `a:b:c:d:e:f:g:h`.
    ##
    ## @param a the first group
    ## @param b the second group
    ## @param c the third group
    ## @param d the fourth group
    ## @param e the fifth group
    ## @param f the sixth group
    ## @param g the seventh group
    ## @param h the eighth group
    ## @returns the address
    ## @example
    ##     var loopback = IpAddress.v6(0, 0, 0, 0, 0, 0, 0, 1);   # ::1
    static v6(a: u16, b: u16, c: u16, d: u16, e: u16, f: u16, g: u16, h: u16): IpAddress {
        var address = IpAddress();
        address._is_v6 = true;
        address._high = ((a as ulong) << 48) | ((b as ulong) << 32) | ((c as ulong) << 16) | (d as ulong);
        address._low = ((e as ulong) << 48) | ((f as ulong) << 32) | ((g as ulong) << 16) | (h as ulong);
        return address;
    }

    ## Returns the IPv4 loopback address, `127.0.0.1`.
    ##
    ## @returns `127.0.0.1`
    static loopback_v4(): IpAddress {
        return v4(127, 0, 0, 1);
    }

    ## Returns the IPv6 loopback address, `::1`.
    ##
    ## @returns `::1`
    static loopback_v6(): IpAddress {
        return v6(0, 0, 0, 0, 0, 0, 0, 1);
    }

    ## Returns the IPv4 unspecified address, `0.0.0.0`. Binding to it listens
    ## on every IPv4 interface.
    ##
    ## @returns `0.0.0.0`
    static unspecified_v4(): IpAddress {
        return IpAddress();
    }

    ## Returns the IPv6 unspecified address, `::`. Binding to it listens on
    ## every IPv6 interface (and, where the system allows dual-stack sockets
    ## by default, such as Linux, on every IPv4 interface too).
    ##
    ## @returns `::`
    static unspecified_v6(): IpAddress {
        return v6(0, 0, 0, 0, 0, 0, 0, 0);
    }

    ## Parses an IPv4 address in dotted decimal (`192.168.0.1`) or an IPv6
    ## address in the RFC 4291 text form (`::1`, `fe80::1:2`,
    ## `::ffff:10.0.0.1`), with an optional scope (`fe80::1%eth0`).
    ##
    ## IPv4 needs exactly four decimal parts from 0 to 255 without leading
    ## zeros. IPv6 takes up to eight groups of one to four hex digits (either
    ## case), at most one `::`, and an optional IPv4 address as the last 32
    ## bits. Brackets and surrounding spaces are not accepted.
    ##
    ## An IPv6 address may end in `%` and a scope: a decimal scope id
    ## (`%3`), or the name of a network interface (`%eth0`), which is looked
    ## up on this machine (so it fails where there is no such interface).
    ##
    ## @param text the address to parse
    ## @returns the address; an error with `is_invalid_input()` when `text` is
    ##   not a valid IPv4 or IPv6 address or names an unknown interface
    ## @example
    ##     var r = IpAddress.parse("10.0.0.300");
    ##     print(r.is_err());   # true: 300 is out of range
    ##     var scoped = IpAddress.parse("fe80::1%7").value();
    ##     print(scoped.scope_id());   # 7
    static parse(text: String): IoResult<IpAddress> {
        var p = unsafe_cast<__ptr<u8>>(text.c_str());
        var n = text.size;
        var v4 = _io_parse_v4(p, n, 0, n);
        if (v4.is_value()) {
            var address = IpAddress();
            address._low = v4.value();
            return IoResult<IpAddress>.ok(address);
        }
        return _io_parse_v6_scoped(text, 0, n, "invalid IP address syntax");
    }

    ## Returns whether this is an IPv4 address.
    ##
    ## @returns true for IPv4, false for IPv6
    is_v4(): bool {
        return !_is_v6;
    }

    ## Returns whether this is an IPv6 address (including an IPv4-mapped one,
    ## `::ffff:a.b.c.d`).
    ##
    ## @returns true for IPv6, false for IPv4
    is_v6(): bool {
        return _is_v6;
    }

    ## Returns the scope id of an IPv6 address: the index of the network
    ## interface it belongs to (the `3` or `eth0` of `fe80::1%3` or
    ## `fe80::1%eth0`), or 0 when it has none. Always 0 for IPv4.
    ##
    ## @returns the scope id, 0 for none
    scope_id(): uint {
        return _scope_id;
    }

    ## Returns this address with scope id `id`, such as the index of the
    ## interface a link-local address is reached through; 0 removes the
    ## scope.
    ##
    ## @param id the scope id, 0 for none
    ## @returns a copy of this address with that scope id
    ## @panics if this is an IPv4 address and `id` is not 0
    ## @example
    ##     var a = IpAddress.parse("fe80::1").value().with_scope_id(2);
    ##     print(a.to_string());   # fe80::1%eth0 where interface 2 is eth0
    with_scope_id(id: uint): IpAddress {
        assert(_is_v6 || id == 0, "an IPv4 address has no scope id");
        var address = IpAddress();
        address._is_v6 = _is_v6;
        address._high = _high;
        address._low = _low;
        address._scope_id = id;
        return address;
    }

    ## Returns whether this is a loopback address: `127.0.0.0/8` for IPv4,
    ## `::1` for IPv6.
    ##
    ## @returns true for a loopback address
    is_loopback(): bool {
        if (_is_v6) {
            return _high == 0 && _low == 1;
        }
        return (_low >> 24) == 127;
    }

    ## Returns whether this is the unspecified address, `0.0.0.0` or `::`.
    ##
    ## @returns true for the unspecified address
    is_unspecified(): bool {
        return _high == 0 && _low == 0;
    }

    ## Returns the address's bytes in network order: 4 for IPv4, 16 for
    ## IPv6.
    ##
    ## @returns a new array of the address bytes
    ## @example
    ##     var bytes = IpAddress.v4(10, 0, 0, 1).to_bytes();   # [10, 0, 0, 1]
    to_bytes(): u8[] {
        var out = Array<u8>();
        ulong first = 0;
        if (!_is_v6) {
            first = 12;
        }
        var i = first;
        while (i < 16) {
            out.append(_byte(i) as u8);
            i = i + 1;
        }
        return out;
    }

    # Byte `i` (0 to 15) of the 16-byte form, IPv4 in bytes 12 to 15.
    _byte(i: ulong): ulong {
        if (i < 8) {
            return (_high >> (56 - 8 * i)) & 255;
        }
        return (_low >> (56 - 8 * (i - 8))) & 255;
    }

    # 16-bit group `i` (0 to 7) of an IPv6 address.
    _group(i: ulong): ulong {
        if (i < 4) {
            return (_high >> (48 - 16 * i)) & 65535;
        }
        return (_low >> (48 - 16 * (i - 4))) & 65535;
    }

    ## Returns the address as text: dotted decimal for IPv4, the RFC 5952
    ## form for IPv6 (lowercase hex, leading zeros dropped, the longest run of
    ## two or more zero groups written `::`, `::ffff:a.b.c.d` for an
    ## IPv4-mapped address). A scope id follows as `%` and the name of its
    ## interface (`fe80::1%eth0`), or the number when no interface on this
    ## machine has that index (`fe80::1%9`).
    ##
    ## @returns the text form, which `IpAddress.parse` reads back
    to_string(): String {
        if (!_is_v6) {
            return _io_v4_text(_low);
        }
        if (_scope_id != 0) {
            var name = _io_sys_interface_name(_scope_id);
            if (name.size == 0) {
                name = $"{_scope_id}";
            }
            return _unscoped_text() + "%" + name;
        }
        return _unscoped_text();
    }

    # The IPv6 text form without the scope.
    _unscoped_text(): String {
        if (_high == 0 && (_low >> 32) == 65535) {
            return "::ffff:" + _io_v4_text(_low & 4294967295);
        }
        # The longest run of zero groups, at least two long; the first wins a tie.
        ulong best_start = 8;
        ulong best_length = 1;
        ulong i = 0;
        while (i < 8) {
            if (_group(i) == 0) {
                var j = i;
                while (j < 8) {
                    if (_group(j) != 0) {
                        break;
                    }
                    j = j + 1;
                }
                if (j - i > best_length) {
                    best_start = i;
                    best_length = j - i;
                }
                i = j;
            } else {
                i = i + 1;
            }
        }
        var out = StringBuilder();
        i = 0;
        while (i < 8) {
            if (i == best_start) {
                out.append("::");
                i = i + best_length;
                continue;
            }
            if (i > 0 && i != best_start + best_length) {
                out.append(":");
            }
            out.append($"{_group(i):x}");
            i = i + 1;
        }
        return out.to_string();
    }

    ## Returns whether two addresses are the same: same family, same bytes
    ## and same scope id. An IPv4 address never equals an IPv6 one, not even
    ## the IPv6 address that maps it.
    ##
    ## @param other the address to compare with
    ## @returns true when both are equal
    ==(other: IpAddress): bool {
        return _is_v6 == other._is_v6 && _high == other._high && _low == other._low && _scope_id == other._scope_id;
    }

    ## Returns whether two addresses differ.
    ##
    ## @param other the address to compare with
    ## @returns true when the family, any byte or the scope id differs
    !=(other: IpAddress): bool {
        return !(this == other);
    }
}

## An IP address and a port: where a socket is bound, or where it connects
## or sends.
##
## Make one with `SocketAddress(address, port)` or `SocketAddress.parse`,
## or get a list from `resolve`. `SocketAddress()` is `0.0.0.0:0`. The text
## form is `address:port` for IPv4 and `[address]:port` for IPv6.
##
## @example
##     import io;
##
##     var any = io.SocketAddress(io.IpAddress.unspecified_v4(), 8080);
##     var local = io.SocketAddress.parse("[::1]:443").value();
##     print(local.port());   # 443
## @see IpAddress
## @see resolve
export struct SocketAddress {
    ## The IP address.
    IpAddress _address;
    ## The port, 0 to 65535.
    u16 _port;

    ## Creates `0.0.0.0:0`, the IPv4 unspecified address with port 0.
    construct() {
        _address = IpAddress();
    }

    ## Creates a socket address from an IP address and a port.
    ##
    ## Port 0 asks the system to choose a free port when binding; read the
    ## one it chose with the socket's `local_address()`.
    ##
    ## @param address the IP address
    ## @param port the port
    construct(address: IpAddress, port: u16) {
        _address = address;
        _port = port;
    }

    ## Parses `a.b.c.d:port` (IPv4) or `[ipv6]:port` (IPv6), with the address
    ## syntax of `IpAddress.parse` (a scope goes inside the brackets,
    ## `[fe80::1%eth0]:80`) and a decimal port from 0 to 65535.
    ##
    ## @param text the socket address to parse
    ## @returns the socket address; an error with `is_invalid_input()` when
    ##   the text is malformed
    ## @example
    ##     var a = SocketAddress.parse("127.0.0.1:8080").value();
    ##     var b = SocketAddress.parse("[::1]:8080").value();
    static parse(text: String): IoResult<SocketAddress> {
        var p = unsafe_cast<__ptr<u8>>(text.c_str());
        var n = text.size;
        var bad = IoResult<SocketAddress>.err(IoError(_io_sys_code_invalid_input(), "invalid socket address syntax"));
        if (n == 0) {
            return bad;
        }
        # Split at the colon before the port: after `]` for IPv6, the only
        # colon for IPv4.
        ulong colon = n;
        var v6 = _io_byte(p, n, 0) == '[';
        if (v6) {
            var close = text.find("]");
            if (close < 0 || (close as ulong) + 1 >= n || _io_byte(p, n, (close as ulong) + 1) != ':') {
                return bad;
            }
            colon = (close as ulong) + 1;
        } else {
            var first = text.find(":");
            if (first < 0) {
                return bad;
            }
            colon = first as ulong;
            if (text.find(":", colon + 1) >= 0) {
                return bad;  # a second colon: IPv6 needs brackets
            }
        }
        var port = _io_parse_port(p, n, colon + 1, n);
        if (port.is_empty()) {
            return bad;
        }
        var address = IpAddress();
        if (v6) {
            var scoped = _io_parse_v6_scoped(text, 1, colon - 1, "invalid socket address syntax");
            if (scoped.is_err()) {
                return IoResult<SocketAddress>.err(scoped.error());
            }
            address = scoped.value();
        } else {
            var value = _io_parse_v4(p, n, 0, colon);
            if (value.is_empty()) {
                return bad;
            }
            address._low = value.value();
        }
        return IoResult<SocketAddress>.ok(SocketAddress(address, port.value() as u16));
    }

    ## Returns the IP address.
    ##
    ## @returns the IP address part
    address(): IpAddress {
        return _address;
    }

    ## Returns the port.
    ##
    ## @returns the port, 0 to 65535
    port(): u16 {
        return _port;
    }

    ## Returns whether the IP address is IPv4.
    ##
    ## @returns true for an IPv4 socket address
    is_v4(): bool {
        return _address.is_v4();
    }

    ## Returns whether the IP address is IPv6.
    ##
    ## @returns true for an IPv6 socket address
    is_v6(): bool {
        return _address.is_v6();
    }

    ## Returns the text form: `a.b.c.d:port` for IPv4, `[ipv6]:port` for
    ## IPv6.
    ##
    ## @returns the text form, which `SocketAddress.parse` reads back
    to_string(): String {
        var address = _address.to_string();
        if (_address.is_v6()) {
            return $"[{address}]:{_port}";
        }
        return $"{address}:{_port}";
    }

    ## Returns whether two socket addresses have equal IP addresses and the
    ## same port.
    ##
    ## @param other the socket address to compare with
    ## @returns true when both are equal
    ==(other: SocketAddress): bool {
        return _address == other._address && _port == other._port;
    }

    ## Returns whether two socket addresses differ.
    ##
    ## @param other the socket address to compare with
    ## @returns true when the address or the port differs
    !=(other: SocketAddress): bool {
        return !(this == other);
    }
}

## Looks up the socket addresses of a host, with `port` attached to each.
##
## A `host` that is already an IP address (as `IpAddress.parse` reads it) is
## returned as is, without a lookup. Anything else goes to the system
## resolver (`getaddrinfo` on POSIX, `GetAddrInfoW` on Windows), which
## consults the hosts file and DNS and blocks until it answers. The addresses
## come in the resolver's order of preference, IPv4 and IPv6 mixed, each at
## most once.
##
## @param host a host name such as `"example.com"` or `"localhost"`, or an IP address
## @param port the port to put in every result
## @returns at least one address; an error with `is_not_found()` when the
##   name has no address, `is_invalid_input()` when `host` is empty, or
##   another resolver error
## @example
##     import io;
##
##     var r = io.resolve("localhost", 8080);
##     if (r.is_ok()) {
##         for (var address in r.value()) {
##             print(address.to_string());   # 127.0.0.1:8080, [::1]:8080, ...
##         }
##     }
export resolve(host: String, port: u16): IoResult<SocketAddress[]> {
    if (host.size == 0) {
        return IoResult<SocketAddress[]>.err(IoError(_io_sys_code_invalid_input(), "empty host name"));
    }
    var literal = IpAddress.parse(host);
    if (literal.is_ok()) {
        var one = Array<SocketAddress>();
        one.append(SocketAddress(literal.value(), port));
        return IoResult<SocketAddress[]>.ok(one);
    }
    var found = _io_sys_resolve(host, port);
    if (found.is_err()) {
        return found;
    }
    # The resolver lists an address once per socket type and protocol it
    # supports even with a type hint on some systems; keep the first of each.
    var unique = Array<SocketAddress>();
    for (var address in found.value()) {
        if (!unique.contains(address)) {
            unique.append(address);
        }
    }
    if (unique.count == 0) {
        return IoResult<SocketAddress[]>.err(IoError(_io_sys_code_not_found(), "no address found for '" + host + "'"));
    }
    return IoResult<SocketAddress[]>.ok(unique);
}

# ── Text helpers ─────────────────────────────────────────────────────────────

# The IPv6 address in text[start, end), with an optional `%` and scope (a
# decimal id or an interface name); `syntax` is the message for malformed
# text.
_io_parse_v6_scoped(text: String, start: ulong, end: ulong, syntax: String): IoResult<IpAddress> {
    var p = unsafe_cast<__ptr<u8>>(text.c_str());
    var n = text.size;
    var bad = IoResult<IpAddress>.err(IoError(_io_sys_code_invalid_input(), syntax));
    var address_end = end;
    var percent = text.find("%", start);
    if (percent >= 0 && (percent as ulong) < end) {
        address_end = percent as ulong;
    }
    var v6 = _io_parse_v6(p, n, start, address_end);
    if (v6.is_empty()) {
        return bad;
    }
    var bits: (high: ulong, low: ulong) = v6.value();
    var address = IpAddress();
    address._is_v6 = true;
    address._high = bits.high;
    address._low = bits.low;
    if (address_end == end) {
        return IoResult<IpAddress>.ok(address);
    }
    var zone = text.substr_bytes(address_end + 1, end - address_end - 1);
    if (zone.size == 0) {
        return bad;
    }
    var id = _io_parse_decimal_u32(zone);
    if (id.is_value()) {
        address._scope_id = id.value();
        return IoResult<IpAddress>.ok(address);
    }
    var index = _io_sys_interface_index(zone);
    if (index == 0) {
        return IoResult<IpAddress>.err(IoError(_io_sys_code_invalid_input(), $"no network interface named '{zone}'"));
    }
    address._scope_id = index;
    return IoResult<IpAddress>.ok(address);
}

# `text` as a decimal number from 0 to 4294967295; none when it is not one.
_io_parse_decimal_u32(text: String): uint? {
    if (text.size == 0 || text.size > 10) {
        return Optional<uint>.Empty;
    }
    ulong value = 0;
    for (var c in text.bytes()) {
        if (!(c as byte).is_digit()) {
            return Optional<uint>.Empty;
        }
        value = value * 10 + (c - '0') as ulong;
    }
    if (value > 4294967295) {
        return Optional<uint>.Empty;
    }
    return Optional<uint>.Value(value as uint);
}

# The dotted-decimal text of the IPv4 address in the low 32 bits of `value`.
_io_v4_text(value: ulong): String {
    return $"{(value >> 24) & 255}.{(value >> 16) & 255}.{(value >> 8) & 255}.{value & 255}";
}

# ── Parsing helpers: each reads p[start, end) of the n bytes at p ───────────

# Dotted decimal: exactly four parts of 0 to 255, no leading zeros. Returns
# the 32-bit value, or none when the text is not an IPv4 address.
_io_parse_v4(p: __ptr<u8>, n: ulong, start: ulong, end: ulong): ulong? {
    ulong value = 0;
    ulong parts = 0;
    var i = start;
    while (parts < 4) {
        var first = _io_byte(p, n, i);
        ulong part = 0;
        ulong digits = 0;
        while (i < end) {
            var c = _io_byte(p, n, i);
            if (!(c as byte).is_digit()) {
                break;
            }
            part = part * 10 + (c - '0') as ulong;
            digits = digits + 1;
            i = i + 1;
            if (digits > 3) {
                return Optional<ulong>.Empty;
            }
        }
        if (digits == 0 || part > 255) {
            return Optional<ulong>.Empty;
        }
        if (digits > 1 && first == '0') {
            return Optional<ulong>.Empty;
        }
        value = (value << 8) | part;
        parts = parts + 1;
        if (parts < 4) {
            if (i >= end) {
                return Optional<ulong>.Empty;
            }
            if (_io_byte(p, n, i) != '.') {
                return Optional<ulong>.Empty;
            }
            i = i + 1;
        }
    }
    if (i != end) {
        return Optional<ulong>.Empty;
    }
    return Optional<ulong>.Value(value);
}

# RFC 4291 text: up to eight hex groups, at most one `::`, an optional
# dotted IPv4 tail. Returns the high and low 64 bits, or none when the text
# is not an IPv6 address.
_io_parse_v6(p: __ptr<u8>, n: ulong, start: ulong, end: ulong): Optional<(high: ulong, low: ulong)> {
    var fail = Optional<(high: ulong, low: ulong)>.Empty;
    if (start >= end) {
        return fail;
    }
    var head = Array<ulong>();  # groups before `::`
    var tail = Array<ulong>();  # groups after it
    var gap = false;
    var i = start;
    if (_io_byte(p, n, i) == ':') {
        if (i + 1 >= end) {
            return fail;
        }
        if (_io_byte(p, n, i + 1) != ':') {
            return fail;
        }
        gap = true;
        i = i + 2;
    }
    while (i < end) {
        var groups = head;
        if (gap) {
            groups = tail;
        }
        var j = i;
        while (j < end) {
            if (_pep_hex_digit(_io_byte(p, n, j)) < 0) {
                break;
            }
            j = j + 1;
        }
        if (j < end && _io_byte(p, n, j) == '.') {
            # The last 32 bits as an IPv4 address.
            var v4 = _io_parse_v4(p, n, i, end);
            if (v4.is_empty()) {
                return fail;
            }
            groups.append(v4.value() >> 16);
            groups.append(v4.value() & 65535);
            i = end;
            break;
        }
        if (j == i || j - i > 4) {
            return fail;
        }
        ulong group = 0;
        while (i < j) {
            group = group * 16 + _pep_hex_digit(_io_byte(p, n, i)) as ulong;
            i = i + 1;
        }
        groups.append(group);
        if (i == end) {
            break;
        }
        if (_io_byte(p, n, i) != ':') {
            return fail;
        }
        i = i + 1;
        if (i < end && _io_byte(p, n, i) == ':') {
            if (gap) {
                return fail;  # a second `::`
            }
            gap = true;
            i = i + 1;
            continue;
        }
        if (i == end) {
            return fail;  # a trailing single colon
        }
    }
    var count = head.count + tail.count;
    if (gap && count > 7) {
        return fail;
    }
    if (!gap && count != 8) {
        return fail;
    }
    var all = Array<ulong>();
    for (var g in head) {
        all.append(g);
    }
    while (all.count + tail.count < 8) {
        all.append(0);
    }
    for (var g in tail) {
        all.append(g);
    }
    var high = (all[0] << 48) | (all[1] << 32) | (all[2] << 16) | all[3];
    var low = (all[4] << 48) | (all[5] << 32) | (all[6] << 16) | all[7];
    return Optional<(high: ulong, low: ulong)>.Value((high: high, low: low));
}

# A decimal port, 0 to 65535, one to five digits; none when the text is not
# one.
_io_parse_port(p: __ptr<u8>, n: ulong, start: ulong, end: ulong): ulong? {
    if (start >= end || end - start > 5) {
        return Optional<ulong>.Empty;
    }
    ulong value = 0;
    var i = start;
    while (i < end) {
        var c = _io_byte(p, n, i);
        if (!(c as byte).is_digit()) {
            return Optional<ulong>.Empty;
        }
        value = value * 10 + (c - '0') as ulong;
        i = i + 1;
    }
    if (value > 65535) {
        return Optional<ulong>.Empty;
    }
    return Optional<ulong>.Value(value);
}
