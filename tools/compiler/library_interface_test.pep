# A Pepper library's interface (`--lib pepper`'s `.pepi`, #220): the checked
# record of its files, written beside its archive and named by its stamp,
# reads back into a program that imports the library without its files,
# and a link summary that calls through a trait is joined again over a
# program's own implementation.

import [Diagnostic] from compiler.diagnostic;
import compiler.driver;
import compiler.incremental;
import [Directory, File, Path] from io;
import [JsonValue] from json;
import compiler.link;
import compiler.sema;
import [TempFolder] from testing;

# A library with a trait, a value struct, a shared struct, a generic, a
# plain function, a function whose summary calls through the trait, and a
# module-scope `static` block.
const _GEO = "export trait Holder {\n    hold(item: String);\n}\n\n[Value]\nexport struct Point {\n    var x: int;\n    var y: int;\n}\n\n[Shared]\nexport struct Tally {\n    const total: int;\n\n    construct(total: int) {\n        this.total = total;\n    }\n}\n\nexport struct Box {\n    var count: int = 0;\n}\n\nextend Box with Holder {\n    hold(item: String) {\n        count += 1;\n    }\n}\n\nexport twice<T>(value: T): T[] {\n    return [value, value];\n}\n\nexport shout(text: String): String {\n    return text + \"!\";\n}\n\nexport give(holder: Holder, item: String) {\n    holder.hold(item);\n}\n\n_hidden(): int {\n    return 1;\n}\n\nexport static {\n    const SIDES = 2 + 2;\n    const NAME = reflect.name<Point>();\n}\n";

# Builds `_GEO` as `geo.pep` into a Pepper library in `root`, in process,
# and returns its archive.
_build_library(root: Path): Path {
    Directory.create_all(root);
    var source = root.join(Path("geo.pep"));
    File.write_text(source, _GEO);
    var archive = root.join(Path(driver.library_file_name(driver.LibraryKind.Pepper, "geo", link.Target())));
    var setup = link.Setup();
    setup.library = "geo";
    setup.pepper_library = true;
    var options = driver.BuildOptions(archive, root.join(Path("build")));
    options.library = Optional<driver.LibraryKind>.Value(driver.LibraryKind.Pepper);
    options.cache = Optional<incremental.Cache>.Value(incremental.Cache(root.join(Path("cache"))));
    options.in_process = true;
    var built = driver.build(link.load_program(source, setup).value(), options);
    if (built.is_err()) {
        print(built.error());
    }
    expect_true(built.is_ok());
    return archive;
}

# Checks `program` in compilation units in `cache`; the diagnostics when
# it fails.
_check(program: link.Program, cache: incremental.Cache): Result<incremental.Checked, String> {
    var checked = incremental.check_compilation_units(
        program,
        incremental.compilation_units(program, "base"),
        cache,
        Optional<incremental.Reused>.Empty,
        program.sources(),
        Array<Diagnostic>(),
        Array<String>(),
        incremental.Clock(false),
        false,
        false
    );
    if (checked.is_ok()) {
        return Result<incremental.Checked, String>.ok(checked.value());
    }
    match (checked.error()) {
        Checking(diagnostics) => {
            var messages = Array<String>();
            for (var d in diagnostics) {
                messages.append(d.message);
            }
            return Result<incremental.Checked, String>.err("\n".join(messages));
        }
        else => {
            return Result<incremental.Checked, String>.err("not checked");
        }
    }
}

# The program of `main` (a file's text) in `root`, which imports the
# library whose archive is in `library`, and has none of its files.
_importer(root: Path, library: Path, main: String): link.Program {
    Directory.create_all(root);
    var path = root.join(Path("main.pep"));
    File.write_text(path, main);
    var setup = link.Setup();
    setup.library_dirs.append(library);
    var program = link.load_program(path, setup).value();
    expect_true(program.errors.is_empty);
    return program;
}

# The index of the root file of the library `program` imports.
_library_root(program: link.Program): uint {
    for (var i in 0..program.files.count) {
        if (program.files[i].interface.is_value() and program.files[i].library_root) {
            return i as uint;
        }
    }
    return 0;
}

[Test]
a_pepper_library_writes_its_interface_beside_its_archive() {
    var folder = TempFolder("library_interface");
    var archive = _build_library(folder.path);
    var path = incremental.interface_path(archive);
    expect_equal(path.extension().value_or(""), link.INTERFACE_EXTENSION);
    var bytes = File.read_bytes(path).value();
    var stamp = link.read_stamps(archive).value()[0];
    expect_equal(stamp.interface, link.interface_hash(bytes));
    expect_equal(stamp.record, link.RECORD_VERSION);
    expect_false(stamp.runtime_interface.is_empty);
    expect_true(stamp.text().contains($"\nrecord {link.RECORD_VERSION}\n"));
    # A library for C has none.
    var static_archive = folder.path.join(
        Path("c")
    ).join(Path(driver.library_file_name(driver.LibraryKind.Static, "geo", link.Target())));
    var options = driver.BuildOptions(static_archive, folder.path.join(Path("build-c")));
    options.library = Optional<driver.LibraryKind>.Value(driver.LibraryKind.Static);
    options.in_process = true;
    var setup = link.Setup();
    setup.library = "geo";
    expect_true(driver.build(link.load_program(folder.path.join(Path("geo.pep")), setup).value(), options).is_ok());
    expect_true(static_archive.is_file());
    expect_false(incremental.interface_path(static_archive).is_file());
    expect_true(link.read_stamps(static_archive).value()[0].interface.is_empty);
}

# Imported by a program that has none of its files, the interface gives
# back the library's declarations: its files as files of the program under
# their own namespaces, the root's exports, the layouts and attributes of
# its structs, generic bodies, the expanded `static` block, and the link
# summaries that stand for the bodies it leaves out. The text that links
# the program keeps the declarations and none of the bodies.
[Test]
the_interface_reads_back_into_a_program_without_the_library() {
    var folder = TempFolder("library_interface_read");
    var archive = _build_library(folder.path.join(Path("geo")));
    var app = folder.path.join(Path("app"));
    var program = _importer(app, archive.parent().value(), "import geo;\n\nmain(): int {\n    return 0;\n}\n");
    var file = _library_root(program);
    var interface = program.files[file].interface.value();
    expect_equal(interface.files.count, 1 as ulong);
    var geo = interface.files[0];
    expect_equal(geo.namespace, "geo/geo");
    expect_equal(program.files[file].namespace, "geo/geo");
    expect_true(geo.root);
    expect_true(geo.exports.contains("Point") and geo.exports.contains("give") and geo.exports.contains("SIDES"));
    expect_false(geo.exports.contains("_hidden"));
    expect_true(geo.text.contains("export shout(text: String): String {"));
    expect_false(geo.text.contains("return text + \"!\";"));
    expect_equal(geo.text.size, _GEO.size);
    var checked = _check(program, incremental.Cache(app.join(Path("cache"))));
    if (checked.is_err()) {
        print(checked.error());
    }
    var read_golden = File.read_to_string(Path("compiler/testdata/library_interface.golden"));
    # A checkout may give it CRLF line ends.
    var golden = read_golden.is_ok() ? read_golden.value().replace("\r\n", "\n") : "";
    var dump = _dump(checked.value().module, file);
    if (golden != dump) {
        print(
            "the library interface reads back otherwise: if a program reads it differently, bump link.RECORD_VERSION; then update compiler/testdata/library_interface.golden to:"
        );
        print(dump);
    }
    expect_true(golden == dump);

    # A record of another version, or none, is refused.
    var other = $"{link.INTERFACE_MAGIC}{link.RECORD_VERSION + 1}\nrecord\n".bytes();
    var empty = link.LibraryInterface("geo", Path("libgeo.pepi"), Path("libgeo.a"));
    expect_true(link.read_interface_bytes(empty, other).is_value());
    expect_true(link.read_interface_bytes(empty, "geo".bytes()).is_value());
}

# A library function whose link summary calls through a trait (`give`)
# keeps its body in the interface: a program that adds an implementation of
# the trait finds the summary stale and makes it again over its own, so a
# `with` block passing a locked value to it is checked as the
# implementation is, neither as the library's alone nor as linking
# everything.
[Test]
a_program_joins_a_library_summary_over_its_own_implementation() {
    var folder = TempFolder("library_interface_join");
    var archive = _build_library(folder.path.join(Path("geo")));
    for (var (name, body, fails) in [("quiet", "count += 1;", false), ("keeper", "items.append(item);", true)]) {
        var root = folder.path.join(Path(name));
        var program = _importer(
            root,
            archive.parent().value(),
            $"import async;\nimport [give, Holder, shout] from geo;\n\nstruct Keeper {{\n    var count: int = 0;\n    var items: Array<String> = Array<String>();\n}}\n\nextend Keeper with Holder {{\n    hold(item: String) {{\n        {body}\n    }}\n}}\n\nconst keepers = async.Mutex<Keeper>(Keeper());\n\nmain(): int {{\n    var line = shout(\"x\");\n    with (var keeper = keepers.lock()) {{\n        give(keeper, line);\n    }}\n    return 0;\n}}\n"
        );
        # The library's compilation unit comes from its interface.
        var units = incremental.compilation_units(program, "base");
        expect_equal(units.count, 3 as ulong);
        expect_equal(units[1].name, "geo/geo");
        var checked = _check(program, incremental.Cache(root.join(Path("cache"))));
        print($"{name}: {checked.is_ok() ? "checked" : checked.error()}");
        if (fails) {
            expect_true(
                checked.is_err() and checked.error().contains("'line' cannot move into the value locked by 'keepers")
            );
        } else {
            expect_true(checked.is_ok());
        }
    }
}

# The library's declarations in `module`, those of file `file`, one per
# line: what a program checks and instantiates against.
_dump(module: sema.Module, file: uint): String {
    var out = StringBuilder();
    for (var st in module.structs) {
        if (st.loc.file != file) {
            continue;
        }
        var attributes = Array<String>();
        for (var attribute in st.attributes) {
            attributes.append(sema.attribute_name(attribute).value_or("?"));
        }
        out.append($"struct {st.name} [{",".join(attributes)}] traits");
        for (var t in st.traits) {
            out.append($" {t}");
        }
        out.append("\n");
        for (var field in st.field_members) {
            out.append($"  field {field.is_const ? "const" : "var"} {field.name}: {field.ty}\n");
        }
        for (var method in st.method_members) {
            _dump_function(out, module, sema.method_key(st.name, method.name), method, "  method");
        }
        for (var constructor in st.constructors) {
            _dump_function(out, module, sema.method_key(constructor.name, "__ctor"), constructor, "  constructor");
        }
    }
    for (var trait_def in module.traits) {
        if (trait_def.loc.file == file) {
            out.append($"trait {trait_def.name}\n");
        }
    }
    for (var function in module.functions) {
        if (function.loc.file == file) {
            _dump_function(out, module, function.name, function, "function");
        }
    }
    for (var global in module.globals) {
        if (global.loc.file == file) {
            var value = global.default.is_value() ? _without_locs(global.default.value().to_json()).to_string() : "";
            out.append($"global {global.is_const ? "const" : "var"} {global.name}: {global.ty} = {value}\n");
        }
    }
    return out.to_string();
}

# One function of `_dump`: its signature, whether its body is kept, and its
# link summary.
_dump_function(out: StringBuilder, module: sema.Module, key: String, function: sema.FunctionDef, what: String) {
    var parameters = Array<String>();
    for (var p in function.parameters) {
        parameters.append($"{p.name}: {p.ty}");
    }
    bool body = function.body.is_value() or function.pending_body.is_value();
    var summary = module.checked.summaries.try_get(key);
    var (_, text) = summary.is_value() ? summary.value() : (sema.Loc(), "none");
    out.append(
        $"{what} {function.name}({", ".join(parameters)}): {function.ty} {body ? "body" : "stripped"} summary {sema.summary_without_place(text).replace("\n", " | ")}\n"
    );
}

# `value` without its locations, which depend on the program's files.
_without_locs(value: JsonValue): JsonValue {
    match (value) {
        Array(items) => {
            var out = JsonValue.array();
            for (var item in items) {
                out.append(_without_locs(item));
            }
            return out;
        }
        Object(members) => {
            var out = JsonValue.object();
            for (var (key, member) in members) {
                if (!key.ends_with("loc")) {
                    out[key] = _without_locs(member);
                }
            }
            return out;
        }
        else => {
            return value;
        }
    }
}
