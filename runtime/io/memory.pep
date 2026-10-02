## `ByteReader` and `ByteWriter`: a `Reader` over bytes already in memory,
## and a `Writer` that collects what is written into memory, for code that
## takes a stream when the data is in an array.

import "stream";
import "types";

## A `Reader` over an array of bytes: each `read` takes the next bytes of
## the array, and the stream ends after its last byte.
##
## The reader keeps a reference to the array and does not copy it; changing
## the array while reading changes what is read.
##
## @example
##     import io;
##
##     var data = "one\ntwo\n".bytes();
##     var count = 0;
##     for (var line in io.ByteReader(data).lines()) {
##         count += 1;
##     }
##     assert(count == 2, "two lines");
export struct ByteReader {
    ## The bytes being read.
    var _data: u8[];
    ## The index in `_data` of the next byte to read.
    var _position: ulong;

    ## Makes a reader positioned at the first byte of `data`.
    ##
    ## @param data the bytes to read
    construct(data: u8[]) {
        _data = data;
    }

    ## The number of bytes not read yet.
    var remaining: ulong {
        get {
            return _data.count - _position;
        }
    }

    ## Appends up to `max` of the next bytes to `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read
    ## @returns the number of bytes appended, 0 once every byte has been read
    read(buffer: u8[], max: ulong): IoResult<ulong> {
        var count = _data.count - _position;
        if (count > max) {
            count = max;
        }
        buffer._append_raw(_data._data + _position, count);
        _position += count;
        return IoResult<ulong>.ok(count);
    }
}

extend ByteReader with Reader;

## A `Writer` that appends everything written to an array in memory,
## `bytes`.
##
## @example
##     import io;
##
##     var out = io.ByteWriter();
##     out.print("n = ");
##     out.print_line(3);
##     assert(out.bytes == "n = 3\n".bytes(), "collected");
export struct ByteWriter {
    ## The bytes written so far, in order.
    var bytes: u8[];

    ## Makes a writer with nothing written yet.
    construct() {
        bytes = Array<u8>();
    }

    ## Appends all of `data` to `bytes`.
    ##
    ## @param data the bytes to write
    ## @returns the number of bytes written: always `data.count`
    write(data: u8[]): IoResult<ulong> {
        bytes.append_all(data);
        return IoResult<ulong>.ok(data.count);
    }

    ## Appends all of `data` to `bytes`.
    ##
    ## @param data the bytes to write
    ## @returns an Ok result; writing to memory does not fail
    write_all(data: u8[]): IoResult<void> {
        bytes.append_all(data);
        return IoResult<void>.ok();
    }
}

extend ByteWriter with Writer;
