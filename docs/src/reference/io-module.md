<!-- Generated from runtime/io/module.pep by `pep-doc reference`. Do not edit. -->

# The io module

Files, directories, paths, and sockets, modeled on Rust's `std::fs`,
`std::path` and `std::net`.

Unlike the rest of the standard library, `io` is a module: bring it in with
`import io` (and write `io.File`, `io.Path`) or import names directly with
`import [File, Path] from io`. Every fallible operation returns an
[`IoResult<T>`](io-types.md#ioresult), a `Result` whose error is an
[`IoError`](io-types.md#ioerror).

- [Path](io-path.md): building, splitting, and inspecting paths
- [File](io-file.md): opening, reading, and writing files, and whole-file helpers
- [Directory](io-directory.md): listing, creating, and removing directories
- [Network addresses](io-address.md): `IpAddress`, `SocketAddress`, and `resolve`
- [Sockets](io-socket.md): `TcpListener`, `Incoming`, `SharedTcpListener`, `TcpStream`, `SocketTransfer`, and `UdpSocket`
- [Unix domain sockets](io-unix.md): `UnixListener`, `SharedUnixListener`, `UnixStream`, and `UnixDatagram`
- [Streams](io-stream.md): the `Reader` and `Writer` traits, `lines()` and `chunks()`
- [Streams in memory](io-memory.md): `ByteReader` and `ByteWriter`
- [Print](io-print.md): deprecated; use `Writer`
- [Errors and platform types](io-types.md): `IoError`, `ErrorKind`, `IoResult`, and handle types

**Example**
```pepper
import io;

main(): int {
    var path = io.Directory.temp().join("greeting.txt");
    assert(io.File.write_text(path, "hello").is_ok(), "write");
    assert(io.File.read_to_string(path).value() == "hello", "read back");
    io.File.remove(path);
    return 0;
}
```

Source: `runtime/io/module.pep`
