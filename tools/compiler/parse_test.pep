# The compiler's parser in Pepper builds the same syntax tree as the Rust
# parser for every source file in the repository: their JSON forms, from
# `compiler.parse` here and from `pep-build --emit-ast=json`, match byte
# for byte.

import io;
import [Directory, File, Path] from io;
import compiler.parse;
import process;

# The files are split in parts, each a test of its own, so they run side
# by side.
[Test]
parses_every_source_file_as_the_rust_parser_does_part_1() {
    parses_sources(0);
}

[Test]
parses_every_source_file_as_the_rust_parser_does_part_2() {
    parses_sources(1);
}

[Test]
parses_every_source_file_as_the_rust_parser_does_part_3() {
    parses_sources(2);
}

[Test]
parses_every_source_file_as_the_rust_parser_does_part_4() {
    parses_sources(3);
}

[Test]
parses_every_source_file_as_the_rust_parser_does_part_5() {
    parses_sources(4);
}

[Test]
parses_every_source_file_as_the_rust_parser_does_part_6() {
    parses_sources(5);
}

[Test]
parses_every_source_file_as_the_rust_parser_does_part_7() {
    parses_sources(6);
}

[Test]
parses_every_source_file_as_the_rust_parser_does_part_8() {
    parses_sources(7);
}

const PARSE_PARTS: ulong = 8;

# Checks every `PARSE_PARTS`th source file of the repository, from the `part`th.
parses_sources(part: ulong) {
    var compiler = process.find_companion("pep-build");
    expect_true(compiler.is_value(), "pep-build is beside pep-test or on the PATH");
    if (!compiler.is_value()) {
        return;
    }
    var files = Array<Path>();
    # The folders, from the repository's root, whose `.pep` files are
    # checked.
    for (var folder in ["runtime", "tools", "tests", "docs/examples"]) {
        collect_sources(Path("..").join(folder), files);
    }
    expect_true(files.count > 400, "the repository's sources are found from tools/");
    ulong mismatches = 0;
    var i = part;
    while (i < files.count) {
        if (!same_tree(compiler.value(), files[i])) {
            mismatches += 1;
        }
        i += PARSE_PARTS;
    }
    expect_equal(mismatches, 0 as ulong);
}

# Whether the two parsers agree on `file`, reporting where they do not. A
# file the Rust parser rejects is skipped.
same_tree(compiler: Path, file: Path): bool {
    var output = process
        .Command(compiler.to_string())
        .argument("--emit-ast=json")
        .argument(file.to_string())
        .stdout(process.Stream.Pipe)
        .stderr(process.Stream.Pipe)
        .run();
    if (output.is_err() or !output.value().status.success()) {
        return true;
    }
    var expected = output.value().stdout.trim_end();
    var source = File.read_to_string(file);
    if (source.is_err()) {
        print($"{file}: cannot read it");
        return false;
    }
    var module = parse.parse(source.value());
    if (module.is_err()) {
        var error = module.error();
        print($"{file}:{error.span.start}: the Rust parser accepts it, but: {error.message}");
        return false;
    }
    var actual = module.value().to_json().to_string();
    if (actual != expected) {
        print(
            $"{file}: the syntax tree differs from the Rust parser's at byte {first_difference(actual, expected)} of its JSON"
        );
        return false;
    }
    return true;
}

# Appends the `.pep` files under `folder` to `out`, in name order, leaving
# out build folders.
collect_sources(folder: Path, out: Path[]) {
    var listing = Directory.open(folder);
    if (listing.is_err()) {
        return;
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return;
    }
    var names = Array<String>();
    var by_name = HashMap<String, io.DirEntry>();
    for (var entry in entries.value()) {
        names.append(entry.name);
        by_name[entry.name] = entry;
    }
    names.sort((a, b) => a.compare(b));
    for (var name in names) {
        var entry = by_name[name];
        if (entry.is_directory and !name.starts_with(".")) {
            collect_sources(entry.path, out);
        } else if (entry.is_file and name.ends_with(".pep")) {
            out.append(entry.path);
        }
    }
}

first_difference(a: String, b: String): ulong {
    ulong i = 0;
    while (i < a.size and i < b.size and a.byte_at(i) == b.byte_at(i)) {
        i += 1;
    }
    return i;
}
