<!-- Generated from runtime/io/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# The io module

Files, directories, and paths, modeled on Rust's `std::fs` and `std::path`.

Unlike the rest of the standard library, `io` is a module: bring it in with
`import io` (and write `io.File`, `io.Path`) or import names directly with
`import [File, Path] from io`. Every fallible operation returns an
[`IoResult<T>`](io-types.md#ioresult), a `Result` whose error is an
[`IoError`](io-types.md#ioerror).

- [Path](io-path.md): building, splitting, and inspecting paths
- [File](io-file.md): opening, reading, and writing files, and whole-file helpers
- [Directory](io-directory.md): listing, creating, and removing directories
- [Errors and platform types](io-types.md): `IoError`, `IoResult`, and handle types

**Example**
```pepper
    import io;

    main(): int {
        var path = io.Directory.temp().join_str("greeting.txt");
        assert(io.File.write_text(path, "hello").is_ok(), "write");
        assert(io.File.read_to_string(path).value() == "hello", "read back");
        io.File.remove(path);
        return 0;
    }
```

Source: `runtime/io/module.pep`
