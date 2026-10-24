# A file sees another file of its module only through an import of it
# (docs/src/language/visibility.md): every module of the repository, and
# every test file, links and checks clean under that rule. CI runs this on
# each platform, so it checks the files platform selection keeps there.

import compiler.driver;
import [Directory, File, Path] from io;
import compiler.link;

# The repository, from `tools`, where the tests run.
const _REPO = "..";

# Checks every program: each module folder, through a program that imports
# it, and each test file, built for its tests.
[Test]
modules_import_the_files_they_use() {
    var programs = Array<(Path, link.Setup)>();
    for (var base in ["runtime", "tools", "docs/examples", "tests"]) {
        _modules(Path(_REPO).join(Path(base)), programs);
    }
    for (var base in ["runtime", "tools"]) {
        _test_files(Path(_REPO).join(Path(base)), programs);
    }
    var failures = Array<String>();
    for (var (entry, setup) in programs) {
        var loaded = link.load_program(entry, setup);
        if (loaded.is_err()) {
            failures.append($"{entry}:\n{loaded.error()}");
            continue;
        }
        var checked = loaded.value().check();
        if (checked.is_value()) {
            failures.append($"{entry}:\n{checked.value()}");
        }
    }
    for (var failure in failures) {
        print(failure);
    }
    expect_equal(failures.count, 0 as ulong);
}

# Whether `name` is a folder the walk skips: fetched packages and build
# output.
_skipped(name: String): bool {
    return name == ".pep" or name == "target" or name == ".git" or name == "node_modules";
}

# Adds, for each module folder in `dir` and below, a program that imports it:
# its entry, which no file holds (`Setup.sources`), beside the outermost
# folder that is not a module, or in the compiler's project, whose
# dependencies it needs.
_modules(dir: Path, out: Array<(Path, link.Setup)>) {
    var listing = Directory.open(dir);
    if (listing.is_err()) {
        return;
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return;
    }
    if (dir.join(Path("module.pep")).is_file()) {
        var outer = dir.parent().value();
        while (outer.join(Path("module.pep")).is_file()) {
            outer = outer.parent().value();
        }
        var name = _dotted(dir, outer);
        var setup = link.Setup();
        setup.import_dirs.append(outer);
        setup.import_dirs.append(Path(_REPO).join(Path("tools")));
        var at = outer;
        var compiler = Path(_REPO).join(Path("tools")).join(Path("compiler"));
        if (dir.to_string().starts_with(compiler.to_string() + "/")
            or dir.to_string().starts_with(compiler.to_string() + "\\")) {
            name = "compiler." + _dotted(dir, compiler);
            at = compiler;
        }
        var entry = at.join(Path("_imports_test_main.pep"));
        setup.sources[link.path_key(entry)] = $"import {name};\nmain(): int {{\n    return 0;\n}}\n";
        out.append((entry, setup));
    }
    for (var entry in entries.value()) {
        if (entry.is_directory and !_skipped(entry.name)) {
            _modules(entry.path, out);
        }
    }
}

# `dir`'s path below `outer`, its folders joined by dots: a module's name.
_dotted(dir: Path, outer: Path): String {
    var full = dir.to_string();
    var base = outer.to_string();
    var rest = full.substr_bytes(base.size + 1, full.size - base.size - 1);
    return rest.replace("/", ".").replace("\\", ".");
}

# Adds each test file in `dir` and below, built for its tests as `pepc
# --test` builds it.
_test_files(dir: Path, out: Array<(Path, link.Setup)>) {
    var listing = Directory.open(dir);
    if (listing.is_err()) {
        return;
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return;
    }
    for (var entry in entries.value()) {
        if (entry.is_directory) {
            if (!_skipped(entry.name)) {
                _test_files(entry.path, out);
            }
            continue;
        }
        if (!entry.name.ends_with("_test.pep")) {
            continue;
        }
        var text = File.read_to_string(entry.path);
        if (text.is_err()) {
            continue;
        }
        var setup = link.Setup();
        setup.import_dirs.append(Path(_REPO).join(Path("tools")));
        setup.target.build_options[link.TEST_BUILD_OPTION] = "1";
        setup.forced_imports.append(driver.TESTING_MODULE);
        setup.sources[link.path_key(entry.path)] = driver.add_test_main(entry.path, text.value(), setup.target);
        out.append((entry.path, setup));
    }
}
