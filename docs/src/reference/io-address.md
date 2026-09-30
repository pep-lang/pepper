<!-- Generated from runtime/io/address.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Network addresses

Network addresses: `IpAddress` (IPv4 or IPv6), `SocketAddress` (an IP
address and a port), and `resolve`, which turns a host name into socket
addresses.

Source: `runtime/io/address.pep`

## IpAddress

```pepper
struct IpAddress
```

An IPv4 or IPv6 address.

Make one with `IpAddress.v4`, `IpAddress.v6`, `IpAddress.parse`, or one
of the well-known addresses (`loopback_v4()`, `unspecified_v6()`, ...).
`IpAddress()` is the IPv4 unspecified address `0.0.0.0`.

`to_string()` prints IPv4 in dotted decimal (`127.0.0.1`) and IPv6 in the
RFC 5952 form (`::1`, `2001:db8::8a2e:370:7334`); an IPv4-mapped IPv6
address prints as `::ffff:1.2.3.4`. An IPv4 address and the IPv6 address
that maps it are different values.

**See also**
- `SocketAddress`

**Example**
```pepper
    import io;

    var a = io.IpAddress.parse("192.168.1.10").value();
    var b = io.IpAddress.v6(8193, 3512, 0, 0, 0, 0, 0, 1);   # 2001:db8::1
    print(a.is_v4());         # true
    print(b.to_string());     # 2001:db8::1
```

### Constructor

#### IpAddress()

```pepper
construct()
```

Creates the IPv4 unspecified address, `0.0.0.0`.

### Static methods

#### v4

```pepper
static v4(a: u8, b: u8, c: u8, d: u8): IpAddress
```

Creates an IPv4 address from its four bytes, `a.b.c.d`.

**Parameters**
- `a` — the first byte
- `b` — the second byte
- `c` — the third byte
- `d` — the fourth byte

**Returns**
- the address `a.b.c.d`

**Example**
```pepper
    var home = IpAddress.v4(127, 0, 0, 1);
```

#### v6

```pepper
static v6(a: u16, b: u16, c: u16, d: u16, e: u16, f: u16, g: u16, h: u16): IpAddress
```

Creates an IPv6 address from its eight 16-bit groups, `a:b:c:d:e:f:g:h`.

**Parameters**
- `a` — the first group
- `b` — the second group
- `c` — the third group
- `d` — the fourth group
- `e` — the fifth group
- `f` — the sixth group
- `g` — the seventh group
- `h` — the eighth group

**Returns**
- the address

**Example**
```pepper
    var loopback = IpAddress.v6(0, 0, 0, 0, 0, 0, 0, 1);   # ::1
```

#### loopback_v4

```pepper
static loopback_v4(): IpAddress
```

Returns the IPv4 loopback address, `127.0.0.1`.

**Returns**
- `127.0.0.1`

#### loopback_v6

```pepper
static loopback_v6(): IpAddress
```

Returns the IPv6 loopback address, `::1`.

**Returns**
- `::1`

#### unspecified_v4

```pepper
static unspecified_v4(): IpAddress
```

Returns the IPv4 unspecified address, `0.0.0.0`. Binding to it listens
on every IPv4 interface.

**Returns**
- `0.0.0.0`

#### unspecified_v6

```pepper
static unspecified_v6(): IpAddress
```

Returns the IPv6 unspecified address, `::`. Binding to it listens on
every IPv6 interface (and, where the system allows dual-stack sockets
by default, such as Linux, on every IPv4 interface too).

**Returns**
- `::`

#### parse

```pepper
static parse(text: String): IoResult<IpAddress>
```

Parses an IPv4 address in dotted decimal (`192.168.0.1`) or an IPv6
address in the RFC 4291 text form (`::1`, `fe80::1:2`,
`::ffff:10.0.0.1`).

IPv4 needs exactly four decimal parts from 0 to 255 without leading
zeros. IPv6 takes up to eight groups of one to four hex digits (either
case), at most one `::`, and an optional IPv4 address as the last 32
bits. Zone suffixes (`%eth0`), brackets and surrounding spaces are not
accepted.

**Parameters**
- `text` — the address to parse

**Returns**
- the address; an error with `is_invalid_input()` when `text` is not a valid IPv4 or IPv6 address

**Example**
```pepper
    var r = IpAddress.parse("10.0.0.300");
    print(r.is_err());   # true: 300 is out of range
```

### Methods

#### is_v4

```pepper
is_v4(): bool
```

Returns whether this is an IPv4 address.

**Returns**
- true for IPv4, false for IPv6

#### is_v6

```pepper
is_v6(): bool
```

Returns whether this is an IPv6 address (including an IPv4-mapped one,
`::ffff:a.b.c.d`).

**Returns**
- true for IPv6, false for IPv4

#### is_loopback

```pepper
is_loopback(): bool
```

Returns whether this is a loopback address: `127.0.0.0/8` for IPv4,
`::1` for IPv6.

**Returns**
- true for a loopback address

#### is_unspecified

```pepper
is_unspecified(): bool
```

Returns whether this is the unspecified address, `0.0.0.0` or `::`.

**Returns**
- true for the unspecified address

#### to_bytes

```pepper
to_bytes(): u8[]
```

Returns the address's bytes in network order: 4 for IPv4, 16 for
IPv6.

**Returns**
- a new array of the address bytes

**Example**
```pepper
    var bytes = IpAddress.v4(10, 0, 0, 1).to_bytes();   # [10, 0, 0, 1]
```

#### to_string

```pepper
to_string(): String
```

Returns the address as text: dotted decimal for IPv4, the RFC 5952
form for IPv6 (lowercase hex, leading zeros dropped, the longest run of
two or more zero groups written `::`, `::ffff:a.b.c.d` for an
IPv4-mapped address).

**Returns**
- the text form, which `IpAddress.parse` reads back

#### operator ==

```pepper
==(other: IpAddress): bool
```

Returns whether two addresses are the same: same family and same
bytes. An IPv4 address never equals an IPv6 one, not even the IPv6
address that maps it.

**Parameters**
- `other` — the address to compare with

**Returns**
- true when both are equal

#### operator !=

```pepper
!=(other: IpAddress): bool
```

Returns whether two addresses differ.

**Parameters**
- `other` — the address to compare with

**Returns**
- true when the family or any byte differs

## SocketAddress

```pepper
struct SocketAddress
```

An IP address and a port: where a socket is bound, or where it connects
or sends.

Make one with `SocketAddress(address, port)` or `SocketAddress.parse`,
or get a list from `resolve`. `SocketAddress()` is `0.0.0.0:0`. The text
form is `address:port` for IPv4 and `[address]:port` for IPv6.

**See also**
- `IpAddress`
- `resolve`

**Example**
```pepper
    import io;

    var any = io.SocketAddress(io.IpAddress.unspecified_v4(), 8080);
    var local = io.SocketAddress.parse("[::1]:443").value();
    print(local.port());   # 443
```

### Constructors

#### SocketAddress()

```pepper
construct()
```

Creates `0.0.0.0:0`, the IPv4 unspecified address with port 0.

#### SocketAddress()

```pepper
construct(address: IpAddress, port: u16)
```

Creates a socket address from an IP address and a port.

Port 0 asks the system to choose a free port when binding; read the
one it chose with the socket's `local_address()`.

**Parameters**
- `address` — the IP address
- `port` — the port

### Static methods

#### parse

```pepper
static parse(text: String): IoResult<SocketAddress>
```

Parses `a.b.c.d:port` (IPv4) or `[ipv6]:port` (IPv6), with the address
syntax of `IpAddress.parse` and a decimal port from 0 to 65535.

**Parameters**
- `text` — the socket address to parse

**Returns**
- the socket address; an error with `is_invalid_input()` when the text is malformed

**Example**
```pepper
    var a = SocketAddress.parse("127.0.0.1:8080").value();
    var b = SocketAddress.parse("[::1]:8080").value();
```

### Methods

#### address

```pepper
address(): IpAddress
```

Returns the IP address.

**Returns**
- the IP address part

#### port

```pepper
port(): u16
```

Returns the port.

**Returns**
- the port, 0 to 65535

#### is_v4

```pepper
is_v4(): bool
```

Returns whether the IP address is IPv4.

**Returns**
- true for an IPv4 socket address

#### is_v6

```pepper
is_v6(): bool
```

Returns whether the IP address is IPv6.

**Returns**
- true for an IPv6 socket address

#### to_string

```pepper
to_string(): String
```

Returns the text form: `a.b.c.d:port` for IPv4, `[ipv6]:port` for
IPv6.

**Returns**
- the text form, which `SocketAddress.parse` reads back

#### operator ==

```pepper
==(other: SocketAddress): bool
```

Returns whether two socket addresses have equal IP addresses and the
same port.

**Parameters**
- `other` — the socket address to compare with

**Returns**
- true when both are equal

#### operator !=

```pepper
!=(other: SocketAddress): bool
```

Returns whether two socket addresses differ.

**Parameters**
- `other` — the socket address to compare with

**Returns**
- true when the address or the port differs

## resolve

```pepper
resolve(host: String, port: u16): IoResult<SocketAddress[]>
```

Looks up the socket addresses of a host, with `port` attached to each.

A `host` that is already an IP address (as `IpAddress.parse` reads it) is
returned as is, without a lookup. Anything else goes to the system
resolver (`getaddrinfo` on POSIX, `GetAddrInfoW` on Windows), which
consults the hosts file and DNS and blocks until it answers. The addresses
come in the resolver's order of preference, IPv4 and IPv6 mixed, each at
most once.

**Parameters**
- `host` — a host name such as `"example.com"` or `"localhost"`, or an IP address
- `port` — the port to put in every result

**Returns**
- at least one address; an error with `is_not_found()` when the name has no address, `is_invalid_input()` when `host` is empty, or another resolver error

**Example**
```pepper
    import io;

    var r = io.resolve("localhost", 8080);
    if (r.is_ok()) {
        for (var address in r.value()) {
            print(address.to_string());   # 127.0.0.1:8080, [::1]:8080, ...
        }
    }
```
