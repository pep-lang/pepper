## `Reader` and `Writer`: the traits of byte streams, such as a `File`, a
## `TcpStream`, a `UnixStream` or a `tls.TlsStream`, so code can read from
## or write to any of them.

import text;
import "file";
import "socket";
import "sys_posix";
import "sys_windows";
import "types";
import "unix";

## A stream of bytes that can be read: a `File`, `TcpStream`, `UnixStream`
## or `tls.TlsStream`, or any type with `read(buffer, max)`.
##
## A type has the trait by providing `read`; it then gets `lines()` and
## `chunks(size)`, which read the stream as a `for` loop asks for more.
## Take a `Reader` (or `<R: Reader>`) to accept any stream.
##
## @example
##     import io;
##
##     count_lines(source: io.Reader): int {
##         var count = 0;
##         for (var line in source.lines()) {
##             if (line.is_err()) {
##                 break;
##             }
##             count += 1;
##         }
##         return count;
##     }
export trait Reader {
    ## Waits until some bytes are available, then appends up to `max` of
    ## them to `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read
    ## @returns the number of bytes appended, 0 at the end of the stream; an
    ##   error when the stream fails
    read(buffer: u8[], max: ulong): IoResult<ulong>;

    ## Returns an iterator over the rest of the stream's lines, read as it
    ## goes, so a `for` loop handles a large file without reading it all.
    ##
    ## Each element is an `IoResult<String>`: a line without its line ending
    ## (`\n`, or `\r\n`). The last line counts even without a final line
    ## ending, and a stream that ends with one has no empty line after it. A
    ## read error, or a line that is not valid UTF-8 (`is_invalid_input()`),
    ## is yielded as an error and ends the lines. The stream is read in
    ## 64 KiB chunks, so a file's position after the loop is not the end of
    ## the last line returned.
    ##
    ## @returns a new `Lines` positioned before the first line
    ## @example
    ##     var f = File.open(Path("notes.txt")).value();
    ##     for (var line in f.lines()) {
    ##         print(line.value());
    ##     }
    lines(): Lines {
        return Lines(this);
    }

    ## Returns an iterator over the rest of the stream in chunks of at most
    ## `size` bytes, each read as the loop asks for it.
    ##
    ## Each element is an `IoResult<u8[]>`: a new array of what one `read`
    ## returned, which may be fewer than `size` bytes (a socket returns what
    ## has arrived). The iteration ends at the end of the stream; a read
    ## error is yielded and ends it.
    ##
    ## @param size the most bytes in one chunk
    ## @returns a new `Chunks` positioned before the first chunk
    ## @panics if `size` is 0 ("Reader.chunks() needs a size above 0")
    ## @example
    ##     var total = 0;
    ##     for (var chunk in stream.chunks(4096)) {
    ##         total += chunk.value().count;
    ##     }
    chunks(size: ulong): Chunks {
        assert(size > 0, "Reader.chunks() needs a size above 0");
        return Chunks(this, size);
    }
}

## A stream of bytes that can be written: a `File`, `TcpStream`,
## `UnixStream` or `tls.TlsStream`, or any type with `write` and
## `write_all`.
##
## A type has the trait by providing `write` and `write_all(data: u8[])`; it
## then gets `print` and `print_line`, which write the text `to_string` makes
## of a value (the text `$"{value}"` would hold).
##
## @example
##     import io;
##
##     main(): int {
##         var path = io.Directory.temp().join("report.txt");
##         var file = io.File.create(path).value();
##         file.print("total: ");
##         file.print_line(42);
##         file.close();
##         assert(io.File.read_to_string(path).value() == "total: 42\n", "printed");
##         io.File.remove(path);
##         return 0;
##     }
export trait Writer {
    ## Writes what the stream takes in one call, which may be less than all
    ## of `data`.
    ##
    ## @param data the bytes to write
    ## @returns the number of bytes written; an error when the stream fails
    write(data: u8[]): IoResult<ulong>;

    ## Writes all of `data`.
    ##
    ## @param data the bytes to write
    ## @returns an Ok result once every byte is written; an error when the
    ##   stream fails
    write_all(data: u8[]): IoResult<void>;

    ## Writes the text of `value`, with no line break after it: a String as
    ## it is, anything else through `to_string`.
    ##
    ## @typeParam T the type of `value`
    ## @param value the value to print
    ## @returns an Ok result once the text is written; an error as for
    ##   `write_all`
    ## @example
    ##     file.print("n = ");
    ##     file.print(3);   # the file now holds "n = 3"
    print<T>(value: T): IoResult<void> {
        return write_all(to_string(value).bytes());
    }

    ## Writes the text of `value` and a line break (`\n`), as the global
    ## `print` does on standard output.
    ##
    ## @typeParam T the type of `value`
    ## @param value the value to print
    ## @returns an Ok result once the line is written; an error as for
    ##   `write_all`
    ## @example
    ##     file.print_line($"total: {total}");
    ##     file.print_line((1, "two"));   # (1, two)
    print_line<T>(value: T): IoResult<void> {
        return write_all((to_string(value) + "\n").bytes());
    }
}

extend File with Reader;

extend File with Writer;

extend TcpStream with Reader;

extend TcpStream with Writer;

extend UnixStream with Reader;

extend UnixStream with Writer;

## The iterator `Reader.lines()` returns: the lines of a stream, read in
## chunks as the loop asks for them, each as an `IoResult<String>`.
##
## @example
##     var f = File.open(Path("notes.txt")).value();
##     var it = f.lines();
##     while (it.next()) {
##         var line = it.current();
##     }
## @see Reader.lines
export struct Lines {
    ## The stream being read.
    Reader _source;
    ## The last chunk read from the file.
    u8[] _chunk;
    ## The position in `_chunk` of the first byte not yet looked at.
    ulong _position;
    ## The bytes of the line being collected.
    u8[] _line;
    ## Whether the lines have ended (at the end of the file, or after an
    ## error); `next()` then returns false.
    bool _finished;
    ## Whether `_value` holds the element the last `next()` moved to.
    bool _has_value;
    ## The current element.
    IoResult<String> _value;

    ## Makes an iterator over the lines of `source`, from what it reads next.
    ##
    ## @param source the open stream to read
    construct(source: Reader) {
        _source = source;
        _chunk = Array<u8>();
        _line = Array<u8>();
        _value = IoResult<String>.ok("");
    }

    ## Reads the next line.
    ##
    ## Once it returns false it keeps returning false.
    ##
    ## @returns true if there is a current element (a line, or the error that
    ## ends the lines), false at the end of the stream
    next(): bool {
        _has_value = false;
        if (_finished) {
            return false;
        }
        _line.clear();
        while (true) {
            if (_position == _chunk.count) {
                _chunk.clear();
                _position = 0;
                var read = _source.read(_chunk, _io_chunk_size());
                if (read.is_err()) {
                    _finished = true;
                    return _yield(IoResult<String>.err(read.error()));
                }
                if (read.value() == 0) {
                    _finished = true;
                    if (_line.is_empty) {
                        return false;
                    }
                    return _yield_line();
                }
            }
            var byte = _chunk[_position];
            _position += 1;
            if (byte == '\n') {
                return _yield_line();
            }
            _line.append(byte);
        }
    }

    # Makes the collected bytes, without a final `\r`, the current element.
    _yield_line(): bool {
        if (!_line.is_empty && _line.last() == '\r') {
            _line.pop();
        }
        var decoded = text.Utf8.decode(_line);
        if (decoded.is_none()) {
            _finished = true;
            return _yield(IoResult<String>.err(IoError(_io_sys_code_invalid_input(), "line is not valid UTF-8")));
        }
        return _yield(IoResult<String>.ok(decoded.value()));
    }

    # Makes `value` the current element.
    _yield(value: IoResult<String>): bool {
        _value = value;
        _has_value = true;
        return true;
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current line, or the error that ended the lines
    ## @panics if `next()` was never called, or already returned false ("Lines.current() without a line")
    current(): IoResult<String> {
        assert(_has_value, "Lines.current() without a line");
        return _value;
    }
}

extend Lines with Iterator<IoResult<String>>;

## The iterator `Reader.chunks(size)` returns: the rest of a stream, one
## `read` of at most `size` bytes at a time, each as an `IoResult<u8[]>`.
##
## @see Reader.chunks
export struct Chunks {
    ## The stream being read.
    Reader _source;
    ## The most bytes in one chunk.
    ulong _size;
    ## Whether the chunks have ended (at the end of the stream, or after an
    ## error); `next()` then returns false.
    bool _finished;
    ## Whether `_value` holds the element the last `next()` moved to.
    bool _has_value;
    ## The current element.
    IoResult<u8[]> _value;

    ## Makes an iterator over `source` in chunks of at most `size` bytes.
    ##
    ## @param source the open stream to read
    ## @param size the most bytes in one chunk
    construct(source: Reader, size: ulong) {
        _source = source;
        _size = size;
        _value = IoResult<u8[]>.ok(Array<u8>());
    }

    ## Reads the next chunk.
    ##
    ## Once it returns false it keeps returning false.
    ##
    ## @returns true if there is a current element (a chunk, or the error
    ## that ends the chunks), false at the end of the stream
    next(): bool {
        _has_value = false;
        if (_finished) {
            return false;
        }
        var chunk = Array<u8>();
        var read = _source.read(chunk, _size);
        if (read.is_err()) {
            _finished = true;
            _value = IoResult<u8[]>.err(read.error());
            _has_value = true;
            return true;
        }
        if (read.value() == 0) {
            _finished = true;
            return false;
        }
        _value = IoResult<u8[]>.ok(chunk);
        _has_value = true;
        return true;
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current chunk, or the error that ended the chunks
    ## @panics if `next()` was never called, or already returned false ("Chunks.current() without a chunk")
    current(): IoResult<u8[]> {
        assert(_has_value, "Chunks.current() without a chunk");
        return _value;
    }
}

extend Chunks with Iterator<IoResult<u8[]>>;
