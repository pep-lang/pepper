# The compiler's parser parses every source file in the repository. Until
# the self-hosting cutover it was held to build the same syntax tree as the Rust
# parser; the curated programs of link_test, sema_test and passes_test
# now hold the compiler to its diagnostics.

import io;
import [Directory, File, Path] from io;
import compiler.parse;

# The files are split in parts, each a test of its own, so they run side
# by side.
[Test]
parses_every_source_file_part_1() {
    parses_sources(0);
}

[Test]
parses_every_source_file_part_2() {
    parses_sources(1);
}

[Test]
parses_every_source_file_part_3() {
    parses_sources(2);
}

[Test]
parses_every_source_file_part_4() {
    parses_sources(3);
}

[Test]
parses_every_source_file_part_5() {
    parses_sources(4);
}

[Test]
parses_every_source_file_part_6() {
    parses_sources(5);
}

[Test]
parses_every_source_file_part_7() {
    parses_sources(6);
}

[Test]
parses_every_source_file_part_8() {
    parses_sources(7);
}

const PARSE_PARTS: ulong = 8;

# Checks every `PARSE_PARTS`th source file of the repository, from the `part`th.
parses_sources(part: ulong) {
    var files = Array<Path>();
    # The folders, from the repository's root, whose `.pep` files are
    # checked.
    for (var folder in ["runtime", "tools", "tests", "docs/examples"]) {
        collect_sources(Path("..").join(folder), files);
    }
    expect_true(files.count > 400, "the repository's sources are found from tools/");
    ulong failed = 0;
    var i = part;
    while (i < files.count) {
        if (!parses(files[i])) {
            failed += 1;
        }
        i += PARSE_PARTS;
    }
    expect_equal(failed, 0 as ulong);
}

# Whether `file` parses, reporting why when it does not.
parses(file: Path): bool {
    var source = File.read_to_string(file);
    if (source.is_err()) {
        print($"{file}: cannot read it");
        return false;
    }
    var module = parse.parse(source.value());
    if (module.is_err()) {
        var error = module.error();
        print($"{file}:{error.span.start}: {error.message}");
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
