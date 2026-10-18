# io.glob_matches: wildcards, classes, braces and `**`; io.glob: walking a
# folder for the paths a pattern matches.

import io;
import [File, Directory, Path] from io;

[Test]
stars_and_question_marks_stay_within_a_component() {
    expect_true(io.glob_matches("*.pep", "main.pep"));
    expect_true(io.glob_matches("a*", "a"));
    expect_true(io.glob_matches("*.pep", ".pep"));
    expect_false(io.glob_matches("*.pep", "src/main.pep"));
    expect_true(io.glob_matches("src/*.pep", "src/main.pep"));
    expect_true(io.glob_matches("m??n.pep", "main.pep"));
    expect_false(io.glob_matches("m?n.pep", "main.pep"));
    expect_true(io.glob_matches("?", "é"));
    expect_true(io.glob_matches("a*b*c", "aXXbYYc"));
    expect_false(io.glob_matches("a*b*c", "aXXbYY"));
    expect_false(io.glob_matches("main.pep", "Main.pep"));
}

[Test]
double_stars_match_any_number_of_components() {
    expect_true(io.glob_matches("src/**/*.pep", "src/a.pep"));
    expect_true(io.glob_matches("src/**/*.pep", "src/x/y/a.pep"));
    expect_false(io.glob_matches("src/**/*.pep", "lib/a.pep"));
    expect_true(io.glob_matches("**", "a/b/c"));
    expect_true(io.glob_matches("**/test/*", "runtime/io/test/glob_test.pep"));
    expect_true(io.glob_matches("a/**", "a/b"));
    # Not a whole component: the same as `*`.
    expect_false(io.glob_matches("a**b", "a/b"));
    expect_true(io.glob_matches("a**b", "aXb"));
}

[Test]
classes_list_ranges_and_negations() {
    expect_true(io.glob_matches("[abc].txt", "b.txt"));
    expect_false(io.glob_matches("[abc].txt", "d.txt"));
    expect_true(io.glob_matches("file[0-9]", "file7"));
    expect_false(io.glob_matches("file[0-9]", "filex"));
    expect_true(io.glob_matches("[!a]x", "bx"));
    expect_false(io.glob_matches("[^a]x", "ax"));
    expect_true(io.glob_matches("[]]", "]"));
    expect_true(io.glob_matches("[*]", "*"));
    expect_false(io.glob_matches("[*]", "a"));
    expect_false(io.glob_matches("[/]", "/"));
    # Unclosed, the `[` is literal.
    expect_true(io.glob_matches("a[b", "a[b"));
}

[Test]
braces_give_alternatives() {
    expect_true(io.glob_matches("*.{pep,md}", "a.md"));
    expect_true(io.glob_matches("*.{pep,md}", "a.pep"));
    expect_false(io.glob_matches("*.{pep,md}", "a.txt"));
    expect_true(io.glob_matches("{src,lib}/**/x", "lib/a/x"));
    expect_true(io.glob_matches("a{b,c{d,e}}f", "acef"));
    expect_true(io.glob_matches("a{,b}", "a"));
    # Unclosed, the `{` is literal.
    expect_true(io.glob_matches("a{b", "a{b"));
}

[Test]
windows_paths_use_either_separator() {
    var matched = io.glob_matches("src/*.pep", "src\\main.pep");
    [Target(OS(Windows))]
    {
        expect_true(matched);
    }
    [Target(!OS(Windows))]
    {
        expect_false(matched);
    }
}

# The text of each path in `paths`, relative to `root` and with `/`
# separators, joined with ", ".
relative(paths: Path[], root: Path): String {
    var prefix = root.to_string() + Path.separator();
    var texts = Array<String>();
    for (var path in paths) {
        var text = path.to_string();
        if (text.starts_with(prefix)) {
            text = text.substr_bytes(prefix.size, text.size - prefix.size);
        }
        texts.append(text.replace("\\", "/"));
    }
    return ", ".join(texts);
}

touch(path: Path) {
    expect_true(File.write_text(path, "").is_ok());
}

[Test]
glob_lists_the_matching_paths_sorted() {
    var folder = TempFolder("glob_lists_the_matching_paths_sorted");
    var root = folder.path;
    expect_true(Directory.create_all(root.join("src").join("io")).is_ok());
    touch(root.join("README.md"));
    touch(root.join("src").join("main.pep"));
    touch(root.join("src").join("notes.md"));
    touch(root.join("src").join("io").join("glob.pep"));
    var base = root.to_string().replace("\\", "/");
    expect_equal(relative(io.glob(base + "/src/**/*.pep"), root), "src/io/glob.pep, src/main.pep");
    expect_equal(relative(io.glob(base + "/**/*.md"), root), "README.md, src/notes.md");
    expect_equal(relative(io.glob(base + "/src/*"), root), "src/io, src/main.pep, src/notes.md");
    expect_equal(relative(io.glob(base + "/{README.md,src/main.pep}"), root), "README.md, src/main.pep");
    expect_equal(relative(io.glob(base + "/src/**"), root), "src, src/io, src/io/glob.pep, src/main.pep, src/notes.md");
    expect_equal(relative(io.glob(base + "/src/main.pep"), root), "src/main.pep");
    expect_equal(io.glob(base + "/missing/**/*").count, 0);
    expect_equal(io.glob(base + "/src/*.txt").count, 0);
}
