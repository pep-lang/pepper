## Archives: tar files, read entry by entry, extracted safely into a
## directory, or written.
##
## Bring it in with `import archive`. Combine it with `compress` for
## `.tar.gz`: wrap the file in a `compress.DecompressReader` to read one, or
## in a `compress.CompressWriter` to write one. A damaged archive is an
## `io.IoError` whose `is_invalid_input()` holds.
##
## - [Tar archives](archive-tar.md): `TarReader`, `TarWriter`, `TarEntry`,
##   `EntryKind`
##
## @example
##     import archive;
##     import io;
##
##     main(): int {
##         var out = io.ByteWriter();
##         var writer = archive.TarWriter(out);
##         writer.append_file("hello.txt", "hi\n".bytes());
##         writer.finish();
##
##         var reader = archive.TarReader(io.ByteReader(out.bytes));
##         var entry = reader.next_entry().value().value();
##         assert(entry.path == "hello.txt" && entry.size == 3, "the header");
##         assert(reader.read_all().value() == "hi\n".bytes(), "the contents");
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "tar";

export EntryKind;
export TarEntry;
export TarReader;
export TarWriter;
