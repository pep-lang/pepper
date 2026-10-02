# Standard library lookups that may come up empty return an optional.
import io;

main(): int {
    # Array.find returns `ulong?`: the index, or none.
    var names = ["ada", "grace", "linus"];
    var at = names.find("grace");
    assert(at.value() == 1, "grace is at index 1");
    assert(names.find("ken").is_empty(), "ken is not in the array");

    # Path.parent, file_name, file_stem and extension return `Path?` or
    # `String?`: none when the path has no such part.
    var path = io.Path("docs").join("guide.md");
    assert(path.file_name().value() == "guide.md", "file name");
    assert(path.file_stem().value() == "guide", "stem");
    assert(path.extension().value() == "md", "extension");
    assert(path.parent().value() == io.Path("docs"), "parent");

    assert(io.Path("/").parent().is_empty(), "a root has no parent");
    assert(io.Path("notes").parent().is_empty(), "nor does a bare name");
    assert(io.Path("a/..").file_name().is_empty(), "'..' is not a file name");
    assert(io.Path("Makefile").extension().is_empty(), "no dot, no extension");

    # value_or supplies a default when none is an expected outcome.
    var ext = io.Path("Makefile").extension().value_or("txt");
    assert(ext == "txt", "fallback extension");
    return 0;
}
