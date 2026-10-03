//! The `archive` module: tar archives written and read back (long paths
//! through the ustar prefix and pax headers), archives made by GNU tar and
//! Python's tarfile, `.tar.gz` through `compress`, extraction with
//! `strip_components`, unsafe paths (`archive.safe_components`), and damaged archives. Each check
//! returns 0 on success or a distinct negative code per check, and must
//! leave no allocation behind.

use crate::support;

const PROGRAM: &str = r##"
import archive;
import compress;
import io;

writes_and_reads_back(): int {
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
    if (out.bytes.count % 512 != 0) { return -1; }

    var reader = archive.TarReader(io.ByteReader(out.bytes));
    var first = reader.next_entry().value().value();
    if (first.path != "d/" || first.kind != archive.EntryKind.Directory || first.mode != 493) { return -2; }
    var hello = reader.next_entry().value().value();
    if (hello.path != "d/hello.txt" || hello.size != 6 || hello.mode != 493) { return -3; }
    var part = Array<u8>();
    if (reader.read(part, 2).value() != 2) { return -4; }
    if (reader.read_all().value() != "llo\n".bytes()) { return -5; }
    # Contents left unread are skipped.
    var third = reader.next_entry().value().value();
    if (third.path != split || third.size != 5) { return -6; }
    var fourth = reader.next_entry().value().value();
    if (fourth.path != long || fourth.size != 0 || fourth.kind != archive.EntryKind.File) { return -7; }
    var link = reader.next_entry().value().value();
    if (link.kind != archive.EntryKind.Symlink || link.link_target != "t".repeat(150)) { return -8; }
    var streamed = reader.next_entry().value().value();
    if (streamed.size != 1000 || streamed.modified != 1700000000) { return -9; }
    if (reader.read_all().value() != body) { return -10; }
    if (reader.next_entry().value().is_value()) { return -11; }
    if (reader.next_entry().value().is_value()) { return -12; }
    return 0;
}

reads_archives_from_other_tools(): int {
    # GNU format, gzipped: a directory, a 154-byte name ('L' header), a
    # file, a hard link and a symlink.
    u8[] gnu = [31, 139, 8, 0, 0, 0, 0, 0, 2, 3, 237, 215, 77, 10, 194, 48, 16, 5, 224, 172, 61, 69, 78, 208, 230, 111, 154, 173, 7, 232, 37, 34, 136, 138, 53, 45, 26, 193, 227, 27, 187, 16, 90, 20, 113, 145, 40, 205, 251, 54, 41, 165, 187, 215, 55, 100, 66, 63, 212, 44, 49, 17, 89, 162, 241, 140, 230, 231, 248, 44, 13, 41, 99, 173, 48, 227, 251, 134, 72, 50, 78, 44, 131, 235, 37, 184, 51, 231, 172, 80, 85, 93, 213, 235, 182, 247, 187, 246, 224, 143, 9, 243, 127, 145, 251, 51, 127, 165, 237, 228, 95, 136, 127, 139, 37, 203, 120, 139, 252, 147, 11, 177, 255, 254, 47, 85, 225, 22, 24, 44, 32, 255, 71, 169, 27, 99, 222, 207, 127, 169, 166, 243, 95, 107, 21, 63, 231, 2, 253, 79, 174, 139, 163, 159, 123, 119, 218, 174, 208, 133, 82, 251, 239, 18, 143, 218, 143, 253, 23, 205, 236, 254, 103, 73, 53, 232, 127, 14, 174, 27, 246, 14, 221, 47, 186, 255, 155, 159, 247, 127, 182, 255, 73, 169, 133, 102, 92, 230, 24, 78, 184, 255, 215, 151, 12, 251, 255, 87, 249, 199, 253, 79, 16, 227, 202, 101, 216, 1, 10, 207, 31, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 150, 233, 14, 67, 235, 92, 6, 0, 40, 0, 0];
    var reader = archive.TarReader(compress.DecompressReader(io.ByteReader(gnu), compress.Format.Gzip));
    var paths = Array<String>();
    var kinds = Array<archive.EntryKind>();
    while (true) {
        var next = reader.next_entry();
        if (next.is_err()) { return -1; }
        if (next.value().is_empty()) { break; }
        var entry = next.value().value();
        paths.append(entry.path);
        kinds.append(entry.kind);
        if (entry.modified != 1700000000) { return -2; }
        if (entry.path == "top/a.txt" && reader.read_all().value() != "alpha\n".bytes()) { return -3; }
        if (entry.kind == archive.EntryKind.HardLink && entry.link_target != "top/a.txt") { return -4; }
        if (entry.kind == archive.EntryKind.Symlink && entry.link_target != "a.txt") { return -5; }
    }
    if (paths.count != 5 || paths[1] != "top/" + "n".repeat(150) + ".txt") { return -6; }
    if (kinds[0] != archive.EntryKind.Directory || kinds[3] != archive.EntryKind.HardLink) { return -7; }

    # pax format: a non-ASCII path too long for the header.
    u8[] pax = [31, 139, 8, 0, 0, 0, 0, 0, 2, 3, 237, 212, 177, 13, 194, 48, 16, 133, 225, 171, 153, 194, 19, 196, 206, 113, 193, 21, 130, 146, 146, 21, 44, 17, 137, 210, 10, 65, 242, 74, 204, 193, 98, 36, 32, 209, 165, 52, 18, 202, 255, 185, 56, 235, 53, 46, 172, 119, 141, 111, 252, 241, 156, 202, 169, 79, 151, 126, 144, 42, 194, 199, 210, 12, 219, 104, 223, 251, 59, 111, 131, 106, 43, 174, 200, 15, 220, 111, 99, 26, 166, 231, 101, 157, 180, 83, 151, 211, 120, 221, 103, 255, 124, 172, 235, 108, 4, 146, 253, 161, 186, 185, 212, 59, 179, 197, 254, 79, 27, 64, 90, 235, 212, 98, 12, 54, 231, 170, 26, 163, 184, 64, 255, 235, 255, 127, 42, 148, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 224, 143, 189, 0, 203, 96, 171, 45, 0, 40, 0, 0];
    reader = archive.TarReader(io.ByteReader(compress.Gzip.decompress(pax).value()));
    var entry = reader.next_entry().value().value();
    if (entry.path != "p/" + "é".repeat(120) || reader.read_all().value() != "pax".bytes()) { return -8; }
    return 0;
}

extracts_into_a_directory(): int {
    var target = io.Directory.temp().join("SCRATCH");
    io.Directory.remove_all(target);

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
    tar.append_symlink("pkg-1.0/skipped", "src");
    tar.append_file("pkg-1.0/./docs//readme.md", "# pkg\n".bytes());
    tar.finish();
    gzip.finish();

    var reader = archive.TarReader(compress.DecompressReader(io.ByteReader(packed.bytes), compress.Format.Gzip));
    var extracted = reader.extract(target, strip_components = 1);
    if (extracted.is_err()) {
        print(extracted.error().message);
        return -1;
    }
    if (io.File.read_to_string(target.join("src").join("main.pep")).value() != "main(): int { return 0; }\n") { return -2; }
    if (io.File.read_to_string(target.join("copy.pep")).value() != "main(): int { return 0; }\n") { return -3; }
    if (io.File.read_to_string(target.join("docs").join("readme.md")).value() != "# pkg\n") { return -4; }
    if (target.join("skipped").exists()) { return -5; }
    if (target.join("pkg-1.0").exists()) { return -6; }

    # An entry that would land outside the target is refused.
    var names = ["../escape.txt", "/etc/escape", "a/../../escape", "c:\\escape", "a\\..\\escape"];
    for (var name in names) {
        var evil = io.ByteWriter();
        tar = archive.TarWriter(evil);
        tar.append_file(name, "x".bytes());
        tar.finish();
        var result = archive.TarReader(io.ByteReader(evil.bytes)).extract(target);
        if (result.is_ok() || !result.error().is_invalid_input() || !result.error().message.contains("unsafe path")) {
            return -7;
        }
    }
    if (io.Directory.temp().join("escape.txt").exists()) { return -8; }
    io.Directory.remove_all(target);
    return 0;
}

reports_damaged_archives(): int {
    var out = io.ByteWriter();
    var tar = archive.TarWriter(out);
    tar.append_file("a.txt", "x".repeat(600).bytes());
    tar.finish();

    # A header byte changed: the checksum no longer matches.
    var corrupt = out.bytes.clone();
    corrupt[0] = 'b';
    var bad = archive.TarReader(io.ByteReader(corrupt)).next_entry();
    if (bad.is_ok() || !bad.error().message.contains("checksum")) { return -1; }

    # Cut in the middle of the contents.
    var cut = out.bytes.clone();
    cut.truncate(700);
    var reader = archive.TarReader(io.ByteReader(cut));
    reader.next_entry().value();
    var rest = reader.read_all();
    if (rest.is_ok() || !rest.error().is_invalid_input()) { return -2; }

    # Cut in the middle of a header.
    cut = out.bytes.clone();
    cut.truncate(100);
    var header = archive.TarReader(io.ByteReader(cut)).next_entry();
    if (header.is_ok() || !header.error().message.contains("truncated")) { return -3; }

    # An empty stream is an empty archive.
    if (archive.TarReader(io.ByteReader(Array<u8>())).next_entry().value().is_value()) { return -4; }
    return 0;
}

checks_entry_paths(): int {
    var parts = archive.safe_components("a//./b/c.txt").value();
    if (parts.count != 3 || parts[0] != "a" || parts[2] != "c.txt") { return -1; }
    if (archive.safe_components("").value().count != 0) { return -2; }
    for (var unsafe in ["/etc/passwd", "a/../../b", "..", "a\\b", "C:/x", "c:x"]) {
        if (archive.safe_components(unsafe).is_value()) { return -3; }
    }
    var error = io.IoError.invalid_input("data.bin: bad header");
    if (!error.is_invalid_input() || error.message != "data.bin: bad header") { return -4; }
    return 0;
}
"##;

/// Each check is a function of one program, compiled once.
#[test]
fn tar_archives() {
    let program = PROGRAM.replace("SCRATCH", &support::scratch_name("tar_extract"));
    support::jit_cases(&program, &["writes_and_reads_back", "reads_archives_from_other_tools", "extracts_into_a_directory", "reports_damaged_archives", "checks_entry_paths"]);
}
