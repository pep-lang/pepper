# Write a .tar.gz, list it, and extract it.
import archive;
import compress;
import io;

main(): int {
    var folder = io.Directory.temp().join("pepper-compression-tar-example");
    io.Directory.remove_all(folder);
    var path = io.Directory.temp().join("pepper-compression-tar-example.tar.gz");

    # A TarWriter over a gzip CompressWriter over a File.
    var file = io.File.create(path).value();
    var gzip = compress.CompressWriter(file, compress.Format.Gzip);
    var tar = archive.TarWriter(gzip);
    tar.append_directory("app-1.0");
    tar.append_file("app-1.0/main.pep", "main(): int { return 0; }\n".bytes());
    tar.append_file("app-1.0/run.sh", "#!/bin/sh\n".bytes(), mode = 493);
    tar.finish();
    gzip.finish();
    file.close();

    # List the entries.
    var reader = archive.TarReader(compress.DecompressReader(io.File.open(path).value(), compress.Format.Gzip));
    var names = Array<String>();
    while (true) {
        var entry = reader.next_entry().value();
        if (entry.is_empty()) {
            break;
        }
        names.append(entry.value().path);
    }
    assert(names.count == 3 && names[0] == "app-1.0/", "a directory ends with '/'");

    # Extract without the top directory.
    reader = archive.TarReader(compress.DecompressReader(io.File.open(path).value(), compress.Format.Gzip));
    reader.extract(folder, strip_components = 1).value();
    assert(io.File.read_to_string(folder.join("main.pep")).value().starts_with("main"), "extracted");

    io.Directory.remove_all(folder);
    io.File.remove(path);
    return 0;
}
