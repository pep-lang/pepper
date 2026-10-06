# archive: tar archives written and read back (long paths through the ustar
# prefix and pax headers), archives made by GNU tar and Python's tarfile
# (gnu.tar.gz and pax.tar.gz here), `.tar.gz` through compress, extraction
# with `strip_components`, modes, times and symlinks restored by extraction,
# unsafe paths (`archive.safe_components`) and link targets, and damaged
# archives.

import archive;
import compress;
import io;

[Test]
writes_and_reads_back() {
    var out = io.ByteWriter();
    var tar = archive.TarWriter(out);
    var split = "d/" + "x".repeat(140) + "/" + "y".repeat(90);
    var long = "z".repeat(300);
    tar.append_directory("d");
    tar.append_file("d/hello.txt", "hello\n".bytes(), mode = 493);
    tar.append_file(split, "split".bytes());
    tar.append_file(long, Array<u8>());
    tar.append_symlink("link", "t".repeat(150));
    var entry = archive.TarEntry("streamed.bin");
    entry.size = 1000;
    entry.modified = 1700000000;
    var body = Array<u8>();
    while (body.count < 1000) {
        body.append((body.count % 251) as u8);
    }
    tar.append_stream(entry, io.ByteReader(body)).value();
    tar.finish();
    tar.finish();
    expect_equal(out.bytes.count % 512, 0);

    var reader = archive.TarReader(io.ByteReader(out.bytes));
    var first = reader.next_entry().value().value();
    expect_equal(first.path, "d/");
    expect_true(first.kind == archive.EntryKind.Directory);
    expect_equal(first.mode, 493);
    var hello = reader.next_entry().value().value();
    expect_equal(hello.path, "d/hello.txt");
    expect_equal(hello.size, 6);
    expect_equal(hello.mode, 493);
    var part = Array<u8>();
    expect_equal(reader.read(part, 2).value(), 2);
    expect_true(reader.read_all().value() == "llo\n".bytes());
    # Contents left unread are skipped.
    var third = reader.next_entry().value().value();
    expect_equal(third.path, split);
    expect_equal(third.size, 5);
    var fourth = reader.next_entry().value().value();
    expect_equal(fourth.path, long);
    expect_equal(fourth.size, 0);
    expect_true(fourth.kind == archive.EntryKind.File);
    var link = reader.next_entry().value().value();
    expect_true(link.kind == archive.EntryKind.Symlink);
    expect_equal(link.link_target, "t".repeat(150));
    var streamed = reader.next_entry().value().value();
    expect_equal(streamed.size, 1000);
    expect_equal(streamed.modified, 1700000000);
    expect_true(reader.read_all().value() == body);
    expect_false(reader.next_entry().value().is_value());
    expect_false(reader.next_entry().value().is_value());
}

[Test]
reads_a_gnu_tar_archive() {
    # GNU format, gzipped: a directory, a 154-byte name ('L' header), a
    # file, a hard link and a symlink.
    var gnu = io.File.read_bytes(io.Path("archive/test/gnu.tar.gz")).value();
    var reader = archive.TarReader(compress.DecompressReader(io.ByteReader(gnu), compress.Format.Gzip));
    var paths = Array<String>();
    var kinds = Array<archive.EntryKind>();
    while (true) {
        var next = reader.next_entry().value();
        if (next.is_empty()) {
            break;
        }
        var entry = next.value();
        paths.append(entry.path);
        kinds.append(entry.kind);
        expect_equal(entry.modified, 1700000000);
        if (entry.path == "top/a.txt") {
            expect_true(reader.read_all().value() == "alpha\n".bytes());
        }
        if (entry.kind == archive.EntryKind.HardLink) {
            expect_equal(entry.link_target, "top/a.txt");
        }
        if (entry.kind == archive.EntryKind.Symlink) {
            expect_equal(entry.link_target, "a.txt");
        }
    }
    expect_equal(paths.count, 5);
    expect_equal(paths[1], "top/" + "n".repeat(150) + ".txt");
    expect_true(kinds[0] == archive.EntryKind.Directory);
    expect_true(kinds[3] == archive.EntryKind.HardLink);
}

[Test]
reads_a_pax_archive() {
    # pax format, from Python's tarfile: a non-ASCII path too long for the
    # header.
    var pax = io.File.read_bytes(io.Path("archive/test/pax.tar.gz")).value();
    var reader = archive.TarReader(io.ByteReader(compress.Gzip.decompress(pax).value()));
    var entry = reader.next_entry().value().value();
    expect_equal(entry.path, "p/" + "é".repeat(120));
    expect_true(reader.read_all().value() == "pax".bytes());
}

[Test]
extracts_into_a_directory() {
    var folder = TempFolder("extracts_into_a_directory");
    var target = folder.path;

    # A .tar.gz with everything under one top directory, as GitHub serves.
    var packed = io.ByteWriter();
    var gzip = compress.CompressWriter(packed, compress.Format.Gzip);
    var tar = archive.TarWriter(gzip);
    tar.append_directory("pkg-1.0");
    tar.append_file("pkg-1.0/src/main.pep", "main(): int { return 0; }\n".bytes());
    # A hard link names an earlier entry; it becomes a copy.
    var link = archive.TarEntry("pkg-1.0/copy.pep", archive.EntryKind.HardLink);
    link.link_target = "pkg-1.0/src/main.pep";
    tar.append(link, Array<u8>());
    tar.append_symlink("pkg-1.0/sources", "src");
    tar.append_file("pkg-1.0/./docs//readme.md", "# pkg\n".bytes());
    tar.finish();
    gzip.finish();

    var reader = archive.TarReader(compress.DecompressReader(io.ByteReader(packed.bytes), compress.Format.Gzip));
    reader.extract(target, strip_components = 1).value();
    expect_equal(io.File.read_to_string(target.join("src").join("main.pep")).value(), "main(): int { return 0; }\n");
    expect_equal(io.File.read_to_string(target.join("copy.pep")).value(), "main(): int { return 0; }\n");
    expect_equal(io.File.read_to_string(target.join("docs").join("readme.md")).value(), "# pkg\n");
    # The symlink is made, except on Windows.
    var sources = target.join("sources").symlink_metadata();
    [Target(!OS(Windows))]
    {
        expect_true(sources.is_ok());
        expect_true(sources.value().is_symlink);
        expect_true(target.join("sources").join("main.pep").is_file());
    }
    [Target(OS(Windows))]
    {
        expect_true(sources.is_err());
    }
    expect_false(target.join("pkg-1.0").exists());

    # An entry that would land outside the target is refused.
    var names = ["../escape.txt", "/etc/escape", "a/../../escape", "c:\\escape", "a\\..\\escape"];
    for (var name in names) {
        var evil = io.ByteWriter();
        tar = archive.TarWriter(evil);
        tar.append_file(name, "x".bytes());
        tar.finish();
        var result = archive.TarReader(io.ByteReader(evil.bytes)).extract(target);
        expect_true(result.is_err());
        expect_true(result.error().is_invalid_input());
        expect_true(result.error().message.contains("unsafe path"));
    }
    expect_false(io.Directory.temp().join("escape.txt").exists());
}

[Test]
restores_modes_times_and_links() {
    var folder = TempFolder("restores_modes_times_and_links");
    var target = folder.path.join("modes");
    var outside = folder.path.join("outside");
    io.File.write_text(outside, "outside");

    var out = io.ByteWriter();
    var tar = archive.TarWriter(out);
    var bin = archive.TarEntry("bin", archive.EntryKind.Directory);
    bin.mode = 365;  # octal 555: nothing can be added to it once extracted
    bin.modified = 1600000000;
    tar.append(bin, Array<u8>());
    var run = archive.TarEntry("bin/run.sh", archive.EntryKind.File);
    run.mode = 2541;  # octal 4755: setuid is never applied
    run.modified = 1500000000;
    run.size = 10;
    tar.append(run, "#!/bin/sh\n".bytes());
    tar.append_file("notes.txt", "notes".bytes(), mode = 420);
    var copy = archive.TarEntry("bin/again.sh", archive.EntryKind.HardLink);
    copy.link_target = "bin/run.sh";
    copy.mode = 493;
    tar.append(copy, Array<u8>());
    tar.append_symlink("bin/latest", "run.sh");
    tar.append_symlink("up", "bin/../notes.txt");
    # These would reach outside `target` and are skipped.
    tar.append_symlink("escape", "../outside");
    tar.append_symlink("absolute", "/etc/passwd");
    tar.append_symlink("bin/deep", "../../outside");
    # A link made inside another link could land anywhere.
    tar.append_symlink("hop", ".");
    tar.append_symlink("hop/escape", "../outside");
    tar.finish();

    archive.TarReader(io.ByteReader(out.bytes)).extract(target).value();
    var script = target.join("bin").join("run.sh").metadata().value();
    expect_equal(script.modified, 1500000000000000000);
    expect_equal(io.File.read_to_string(target.join("bin").join("run.sh")).value(), "#!/bin/sh\n");
    var directory = target.join("bin").metadata().value();
    expect_equal(directory.modified, 1600000000000000000);
    expect_equal(target.join("bin").join("again.sh").metadata().value().modified, 0);
    [Target(OS(Linux) || OS(Mac))]
    {
        expect_equal(script.permissions, 493);
        expect_equal(directory.permissions, 365);
        expect_equal(target.join("notes.txt").metadata().value().permissions, 420);
        expect_equal(target.join("bin").join("again.sh").metadata().value().permissions, 493);
    }
    [Target(!OS(Windows))]
    {
        expect_true(target.join("bin").join("latest").read_link().value() == io.Path("run.sh"));
        expect_equal(io.File.read_to_string(target.join("up")).value(), "notes");
        expect_true(target.join("hop").read_link().value() == io.Path("."));
    }
    for (var name in ["escape", "absolute", "bin/deep", "hop/escape"]) {
        expect_true(target.join(name).symlink_metadata().is_err());
    }

    # Extracting again replaces a symlink in a file's place, never writing
    # through it.
    [Target(OS(Linux) || OS(Mac))]
    {
        # Only POSIX applied the entry's mode (octal 555). On Windows the
        # permissions are the attribute word, where 493 sets the read-only
        # attribute, which then kept the folder from being removed (#724).
        target.join("bin").set_permissions(493);
    }
    io.File.remove(target.join("notes.txt"));
    [Target(!OS(Windows))]
    {
        io.File.symlink(outside, target.join("notes.txt")).value();
    }
    out = io.ByteWriter();
    tar = archive.TarWriter(out);
    tar.append_file("notes.txt", "new".bytes());
    tar.finish();
    archive.TarReader(io.ByteReader(out.bytes)).extract(target).value();
    expect_equal(io.File.read_to_string(target.join("notes.txt")).value(), "new");
    expect_equal(io.File.read_to_string(outside).value(), "outside");
}

[Test]
reports_damaged_archives() {
    var out = io.ByteWriter();
    var tar = archive.TarWriter(out);
    tar.append_file("a.txt", "x".repeat(600).bytes());
    tar.finish();

    # A header byte changed: the checksum no longer matches.
    var corrupt = out.bytes.clone();
    corrupt[0] = 'b';
    var bad = archive.TarReader(io.ByteReader(corrupt)).next_entry();
    expect_true(bad.is_err());
    expect_true(bad.error().message.contains("checksum"));

    # Cut in the middle of the contents.
    var cut = out.bytes.clone();
    cut.truncate(700);
    var reader = archive.TarReader(io.ByteReader(cut));
    reader.next_entry().value();
    var rest = reader.read_all();
    expect_true(rest.is_err());
    expect_true(rest.error().is_invalid_input());

    # Cut in the middle of a header.
    cut = out.bytes.clone();
    cut.truncate(100);
    var header = archive.TarReader(io.ByteReader(cut)).next_entry();
    expect_true(header.is_err());
    expect_true(header.error().message.contains("truncated"));

    # An empty stream is an empty archive.
    expect_false(archive.TarReader(io.ByteReader(Array<u8>())).next_entry().value().is_value());
}

[Test]
checks_entry_paths() {
    var parts = archive.safe_components("a//./b/c.txt").value();
    expect_equal(parts.count, 3);
    expect_equal(parts[0], "a");
    expect_equal(parts[2], "c.txt");
    expect_equal(archive.safe_components("").value().count, 0);
    for (var unsafe in ["/etc/passwd", "a/../../b", "..", "a\\b", "C:/x", "c:x"]) {
        expect_false(archive.safe_components(unsafe).is_value());
    }
    var error = io.IoError.invalid_input("data.bin: bad header");
    expect_true(error.is_invalid_input());
    expect_equal(error.message, "data.bin: bad header");
}
