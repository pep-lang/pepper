# Find files by pattern with io.glob, and test a path with io.glob_matches.
import io;

main(): int {
    var folder = io.Directory.temp().join("pepper-files-glob-example");
    io.Directory.remove_all(folder);
    io.Directory.create_all(folder.join("src").join("net")).value();
    io.File.write_text(folder.join("README.md"), "").value();
    io.File.write_text(folder.join("src").join("main.pep"), "").value();
    io.File.write_text(folder.join("src").join("net").join("http.pep"), "").value();

    # `**` crosses directories; `*` stays within one name. Patterns use `/`
    # on every system, and the paths come back sorted.
    var base = folder.to_string().replace("\\", "/");
    var sources = io.glob(base + "/src/**/*.pep");
    assert(sources.count == 2, "main.pep and net/http.pep");
    assert(io.glob(base + "/*.{md,txt}").count == 1, "README.md");

    # Matching text alone touches no files.
    assert(io.glob_matches("src/**/*.pep", "src/net/http.pep"), "matches");
    assert(!io.glob_matches("*.pep", "src/main.pep"), "`*` stops at `/`");
    assert(io.glob_matches("file[0-9].txt", "file7.txt"), "a class");

    io.Directory.remove_all(folder).value();
    return 0;
}
