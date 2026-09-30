# Networking

The `io` module has TCP and UDP sockets, IP and socket addresses, and host
name lookup. Every call blocks the calling thread until it completes, like
`File`. To serve several connections at once, give each one its own
[thread](threads.md). An event loop that runs many connections on a few
threads is planned (see [Current status](#current-status)).

## Addresses

An `IpAddress` is an IPv4 or IPv6 address. A `SocketAddress` is an IP
address and a port:

```pepper
{{#include ../../examples/networking-addresses.pep}}
```

- `IpAddress.v4(a, b, c, d)` and `IpAddress.v6(a, ..., h)` build an address
  from its bytes or its eight 16-bit groups. `loopback_v4()`,
  `loopback_v6()`, `unspecified_v4()` (`0.0.0.0`) and `unspecified_v6()`
  (`::`) are the well-known ones. `IpAddress()` is `0.0.0.0`.
- `IpAddress.parse` reads dotted decimal IPv4 and the RFC 4291 text form of
  IPv6, and `to_string()` prints the RFC 5952 form: lowercase,
  zeros compressed, `::ffff:1.2.3.4` for an IPv4-mapped address. Parsing and
  printing are the same on every platform.
- `SocketAddress(address, port)` or `SocketAddress.parse("1.2.3.4:80")`
  make a socket address. IPv6 takes brackets: `[::1]:80`.
- `resolve(host, port)` looks a host name up with the system resolver (the
  hosts file and DNS) and returns every address it has, with `port` attached.
  An IP address is returned as is. A name with no address fails with
  `is_not_found()`.

## TCP

A `TcpListener` waits for connections. Each `TcpStream` is one connection:

```pepper
{{#include ../../examples/networking-tcp.pep}}
```

- `TcpListener.bind(address)` listens on a local address. Port 0 lets the
  system pick a free port, and `local_address()` says which one it picked.
  `accept()` waits for the next connection and returns the stream and the
  peer's address as a [tuple](tuples.md).
- `TcpStream.connect(address)` connects to an address.
  `TcpStream.connect_host(host, port)` resolves a name and tries each of its
  addresses in turn.
- `read(buffer, max)` waits until some data arrives, then appends up to `max`
  bytes of it to `buffer`, the same way `File.read` does. It returns 0 once
  the peer has closed its side. `read_exact(buffer, count)` loops until
  `count` bytes have arrived.
- `write(data)` sends what the system will take in one call.
  `write_all(data)` and `write_string(text)` loop until everything is sent.
- `shutdown_write()` tells the peer that nothing more is coming, while this
  side can still read.
- `set_no_delay(true)` sends small writes immediately instead of combining
  them.
- `local_address()` and `peer_address()` return the two ends of the
  connection.

## UDP

A `UdpSocket` sends and receives datagrams. Each one arrives whole or not
at all, and in no guaranteed order:

```pepper
{{#include ../../examples/networking-udp.pep}}
```

- `UdpSocket.bind(address)` opens a socket on a local address.
- `send_to(data, address)` sends one datagram.
  `receive_from(buffer, max)` waits for one datagram, appends it to
  `buffer`, and returns the byte count and the sender. The part of a
  datagram beyond `max` bytes is lost.
- After `connect(address)`, `send` and `receive` use that peer, and
  datagrams from anyone else are dropped.
- `set_broadcast(true)` allows sending to a broadcast address.

## Errors

Every operation returns an `IoResult`. Besides the file-system predicates,
`IoError` has these for networking:

| Predicate | When |
| --- | --- |
| `is_connection_refused()` | nothing listens at the address |
| `is_connection_reset()` | the peer reset or closed the connection (writing to a closed connection included) |
| `is_address_in_use()` | another socket already has the address and port |
| `is_address_not_available()` | the IP address is not one of this machine's |
| `is_timed_out()` | the peer never answered |
| `is_not_found()` | `resolve` found no address for the name |

Writing to a closed connection never raises `SIGPIPE`, so it cannot kill
the process. The write returns an error instead.

## Closing

A socket closes when the last reference to it goes, like a `File`, and
`close()` closes it earlier and reports any error. A socket cannot be
copied, so it cannot go through a [channel](threads.md#channels) to another
thread. Use it on the thread that made it.

On POSIX a listener sets `SO_REUSEADDR`, so a server can restart right
away. On Windows it does not, because there that option would let another
program take over the port.

## Current status

- Every call blocks its thread. There are no timeouts, no non-blocking mode,
  and no way to wait on several sockets at once yet. The planned event loop
  (green threads over epoll, kqueue, IOCP and io_uring) will park the
  calling task instead of blocking the thread, with no change to this API.
- Unix domain sockets and TLS are not supported yet.
- IPv6 scope ids (`fe80::1%eth0`) are not supported.

The reference pages for [addresses](../reference/io-address.md) and
[sockets](../reference/io-socket.md) document every method.
