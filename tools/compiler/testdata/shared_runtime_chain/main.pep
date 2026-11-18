# Releases a chain that runs through the runtime's
# `compress.DecompressReader` and the program's `Wrap` in turn, at the depth
# given, shallow and deep enough to overflow the stack if each release
# recursed into the next. Built with `--runtime=shared`, the runtime
# library's structs cannot steer into the program's, so the chain's last
# release goes through `_pep_release_last`, which bounds the nesting.
# Prints whether it released every `Wrap`.

import compress;
import io;

struct Counter {
    var count: int = 0;
}

struct Wrap {
    var inner: io.Reader;
    var released: Counter;

    construct(inner: io.Reader, released: Counter) {
        this.inner = inner;
        this.released = released;
    }

    destruct {
        released.count += 1;
    }
}

extend Wrap with io.Reader {
    read(buffer: u8[], max: ulong): io.IoResult<ulong> {
        return io.IoResult<ulong>.ok(0);
    }
}

# Builds the chain and releases it, at the local's scope exit.
chain(depth: int, released: Counter) {
    io.Reader reader = io.ByteReader(Array<u8>());
    for (var i in 0..depth) {
        reader = Wrap(compress.DecompressReader(reader, compress.Format.Raw), released);
    }
}

main(args: String[]): int {
    var depth = int.parse(args[1]).value();
    var released = Counter();
    chain(depth, released);
    print($"chain released {released.count == depth}");
    return 0;
}
