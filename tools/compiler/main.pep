# pepc: the Pepper compiler written in Pepper, built and shipped as
# `pep-build`: the same command line, `pep-build --help` for the options.
# `main` declares every option with the `cli` module, which prints
# `--help` from the declarations and reports a command line it cannot
# read (exit status 2). `--target` compiles for another platform,
# `--sysroot` names its system libraries for the link, and `-march`,
# `-mcpu`, `-mtune`, `-m<feature>` choose the CPU
# (`codegen.Cpu.from_options`). `-g` emits debug info (`codegen/debug.pep`),
# and `--debug-static` picks where the debugger shows a `static` block's
# code.
#
# With no `--emit-*` option it builds the program into an executable: `-o
# out`, else the file's stem in the current directory, or the project of
# the current directory with no file. `--lib static|shared` builds a
# library for C instead, with the header of its `[Export]`ed functions
# beside it (`driver/library.pep`), or `--lib xcframework|swift-package`
# one for iOS apps (`driver/xcframework.pep`), or `--lib aar` one for
# Android apps (`driver/aar.pep`), and `--lto=full` (above `-O0`, when
# asked for) optimizes the program as one module before the link
# (`driver/lto.pep`). `--test` builds the test program of the file (or of
# several files of one folder) instead (`driver/test_main.pep`). A build
# keeps each unit's object in the build cache (`driver/cache.pep`): `--cache
# dir`, else `$PEPPER_CACHE_DIR`, else `.pep/cache`; `--no-cache` compiles
# everything, and `--verify-cache` builds again with an empty cache and
# compares the objects (`driver/verify.pep`). `-T time` prints how long
# each stage took, `-T passes` each sema pass, `-T cache` whether each
# unit's object came from the cache, `--Tall` all three.
#
# `--emit-ast[=text|json]`, `--emit-linked`, `--emit-checked`,
# `--emit-model [--emit-model-step N]` and `--emit-steps` print the file's
# syntax tree (`ast/text.pep`), the program after linking, what the checks
# after linking report, the sema model, or the names of the sema steps,
# instead; `--emit-llvm` writes the program's LLVM IR, optimized at the
# `-O` level, to `<build>/<name>.ll`, and `--emit-static` the program's
# source with its `static` blocks expanded (`driver/emit_static.pep`).
#
# Two options are for the children a build starts: `--compile-part dir
# --part N=OBJECT...` compiles parts of a split build (`driver/parts.pep`),
# and `--compilation-unit-worker dir` checks compilation units
# (`driver.compilation_unit_worker`).

import compiler.ast;
import cli;
import compiler.codegen;
import [render_all] from compiler.diagnostic;
import compiler.driver;
import compiler.incremental;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import os;
import compiler.parse;
import process;
import compiler.sema;

# On a stack of `parse.STACK_SIZE`, which the deepest source fits in: the
# main thread's is 1 MiB on Windows.
main(): int {
    return parse.on_compiler_stack(() => _main(process.arguments()));
}

_main(args: String[]): int {
    var parser = cli.Parser("pep-build", "Pepper compiler", version());
    var files = parser.positionals(
        "SOURCE_FILES",
        "The program's entry file. The files it imports are found on their own, so name only this one (several only with `--test`). With none, builds the project whose `pep.toml` is in the current directory or above it"
    );
    var import_dirs = parser.multiple<Path>("", "I", "Add a directory to the import search path", "DIR");
    var imports = parser.multiple("import", help = "Force an import by name", value_name = "NAME");
    var libraries = parser.multiple("", "l", "Link against a library", "LIB");
    var library_dirs = parser.multiple<Path>(
        "",
        "L",
        "Add a directory to the linker's library search path. The folders in `$PEPPER_LIBRARY_PATH` (separated like `PATH`) are searched after these and `[Link(path = ...)]` folders",
        "DIR"
    );
    var defines = parser.multiple(
        "",
        "D",
        "Define a build option: `-D NAME`, or `-D NAME=VALUE` with a value (a bare `NAME` is `NAME=1`, as in C). `[BuildOption(\"NAME\")]` and `BuildOption(NAME)` in `[Target(...)]` select code by it, and `static` blocks read it with `reflect.build_option`. Repeat for more options; of two that name one option, the later wins",
        "NAME[=VALUE]"
    );
    var features = parser.multiple(
        "features",
        "F",
        "Turn on features of the project's package, from its `[features]` in pep.toml: a comma-separated list, or repeat the option. Each feature on defines the build option `<package>_<feature>` and turns on what it lists",
        "NAMES"
    );
    var no_default_features = parser.flag(
        "no-default-features",
        help = "Leave the `default` feature of the project's package off; its dependencies' defaults are still on, unless their entries say `default-features = false`"
    );
    var all_members = parser.flag(
        "all",
        help = "Build every member of the project's workspace, each into its own output, with their features unified; the default in a workspace root that is not a package"
    );
    var member_names = parser.multiple(
        "package",
        "p",
        "Build this member of the project's workspace (by its package name); repeat for more, whose features are then unified",
        "NAME"
    );
    var output = parser.option(
        "",
        "o",
        "Output path: the executable, with `--lib` the library, or with `--emit-static` the folder for the expanded source",
        "OUT"
    );
    var library = parser.option<driver.LibraryKind>(
        "lib",
        help = "Build a library for C code to link instead of an executable: `static` (`libname.a`, `name.lib` on Windows) or `shared` (`libname.so`, `libname.dylib`, `name.dll`), with a C header beside it declaring the `[Export]`ed functions; or for iOS apps, `xcframework` (`name.xcframework`: static libraries for devices and the simulator, with the header and a module map, so Swift can `import name`) or `swift-package` (a folder `name` holding that and a `Package.swift`); or for Android apps, `aar` (`name.aar`: a shared library for each Android ABI, with the header); each named for the output. No `main` is needed",
        value_name = "KIND"
    );
    var bindings = parser.option<driver.BindingsKind>(
        "bindings",
        help = "With `--lib`, also write bindings beside the C header, so an app calls the `[Export]`ed functions with its own language's values: `swift` (`name.swift`, wrappers taking and returning `String` and a class for each struct handle, over the C module `Cname` that the `module.modulemap` it writes declares) or, with `--lib shared`, `java` (`name.jar`, the class `pepper.name.Name` of `static native` methods that Java and Kotlin call, and the JNI functions in `name_jni.c`, compiled into the library). `--lib swift-package` and `--lib aar` write them themselves",
        value_name = "LANGUAGE"
    );
    var entry_function = parser.option(
        "entry",
        help = "The function the program starts in, instead of `main`. It takes no parameters or one `String[]`, as `main` does, and every `main` is left out of the program",
        value_name = "NAME"
    );
    var build_dir = parser.option("build", help = "Build directory", value_name = "DIR");
    var level = parser.option<uint>(
        "",
        "O",
        "Optimization level: `-O0` (the default) through `-O3`; `-O` alone is `-O2`. Without it, `$PEPPER_OPT_LEVEL` when set",
        "LEVEL",
        implicit_value = "2"
    );
    var lto = parser.option<_Lto>(
        "lto",
        help = "Link-time optimization: `full` optimizes the whole program as one module after linking every file's code, so calls between files (into the runtime, for one) inline; `off` optimizes each file alone. The default is `off`: `full` reruns over the whole program on every build, so it suits a release build",
        value_name = "MODE"
    );
    var triple = parser.option(
        "target",
        help = "The platform to compile for, as an LLVM target triple (`aarch64-apple-darwin`, `x86_64-pc-windows-msvc`, `x86_64-unknown-linux-gnu`). The default is the machine the compiler runs on. `[Target(...)]` selects code for it, and linking another platform's executable needs its system libraries (`--sysroot`)",
        value_name = "TRIPLE"
    );
    var sysroot = parser.option(
        "sysroot",
        help = "The directory holding the target's system headers and libraries, passed to the link driver. Without it, `$PEPPER_SYSROOT_<TRIPLE>` (the triple upper-cased, with `_` for `-`) when set",
        value_name = "DIR"
    );
    # What follows each `-m` (`arch=x86-64-v3`, `avx2`), in order.
    var machine = parser.multiple(
        "",
        "m",
        "The CPU to generate code for, with clang's names and meanings: `-march=<cpu>` (x86: `x86-64-v3`, `native`), `-mcpu=<cpu>` (AArch64: `apple-m2`, `native`), `-march=<arch>` (AArch64: `armv8.2-a+crypto`), `-mtune=<cpu>`, and `-m<feature>` / `-mno-<feature>`. The default is clang's for the target (`x86-64`; `apple-m1` on Apple arm64)",
        "OPTION"
    );
    var without_checks = parser.option(
        "no-runtime-checks",
        help = "Remove kinds of runtime check from an optimized build, as a comma-separated list: `overflow` (integer overflow; arithmetic then wraps), `divide` (division by zero and `MIN / -1`; then undefined), `shift` (a count of at least the width; then masked), `bounds` (array and string indexing) and `null` (calls and matches through a null reference), or `all`. Removing `bounds` or `null` gives up memory safety. Ignored, with a warning, at `-O0`",
        value_name = "CHECKS"
    );
    var test = parser.flag(
        "test",
        help = "Build the entry file's tests: keep its `[Test]` functions, define the build option `TEST`, and replace its `main` with one that lists or runs them (`--list`, `--run NAME`). Given several files of one folder, builds the tests of them all into one program, each file keeping the scope it has in any program. `pep-test` builds with it"
    );
    var locked = parser.flag(
        "locked",
        help = "Fail, rather than fetch, when the project's `pep.lock` is out of date with its `pep.toml` (also `PEPPER_LOCKED=1`). The build checks the lock with `pep-package fetch --locked`"
    );
    var offline = parser.flag(
        "offline",
        help = "Fetch nothing over the network: build with what the project's `.pep/deps` and pep-package's download cache hold, and fail on a locked dependency missing from both (also `PEPPER_OFFLINE=1`)"
    );
    var frozen = parser.flag("frozen", help = "Both `--locked` and `--offline`");
    var no_build_scripts = parser.flag(
        "no-build-scripts",
        help = "Fail, rather than run it, when a dependency the build turns on has a build script (`build.pep`), which runs the dependency's code on this machine; the project's own still runs (also `PEPPER_NO_BUILD_SCRIPTS=1`)"
    );
    var build_script = parser.option(
        "build-script",
        help = "Internal: build a package's build script, whose package sees its `[build-dependencies]` from the project in DIR, and run the build scripts of those, not its own. A build gives it to the build of each package's build script",
        value_name = "DIR"
    );
    var ir = parser.flag("emit-llvm", help = "Emit LLVM IR (optimized at the `-O` level)");
    var emit_static = parser.option<_StaticMode>(
        "emit-static",
        help = "Write the program's source with each `static` block replaced by the code it emits, like C's `cc -E`, into the folder `-o` names (default `<name>.static`) instead of compiling it. `--emit-static=keep` also keeps each block, as `#` comments above its expansion",
        value_name = "MODE",
        implicit_value = "expand"
    );
    var debug = parser.flag(
        "emit-debug", "g", "Emit debug info: DWARF on Linux and macOS, CodeView and a `.pdb` on Windows"
    );
    var debug_static = parser.option<_DebugStatic>(
        "debug-static",
        help = "With `-g`, where the debugger shows the code a `static` block emits: `source` (the default), the block as written, stopping on a loop's header once per pass; or `expanded`, a copy of each file with its blocks expanded as `--emit-static` writes them, saved beside the output as `<name>.static.pep`, stepping through the expanded statements. `expanded` builds without the build cache",
        value_name = "VIEW"
    );
    var frame_pointers = parser.flag(
        "frame-pointers",
        help = "Keep the frame pointer in every function, even when optimizing, so profilers and stack walkers unwind the stack cheaply (clang's `-fno-omit-frame-pointer`). `pep-profile` builds with it"
    );
    parser.flag("verbose", "v", "Accepted for compatibility; prints nothing more yet");
    var no_runtime = parser.flag("no-runtime", help = "Skip runtime discovery");
    var emit_ast = parser.option<_AstFormat>(
        "emit-ast",
        help = "Dump the parsed AST instead of compiling: as source-like text (`--emit-ast`, `--emit-ast=text`) or as JSON (`--emit-ast=json`)",
        value_name = "FORMAT",
        implicit_value = "text"
    );
    var linked = parser.flag(
        "emit-linked",
        help = "Load and link the program instead of compiling it, and print every file's syntax tree after linking, with the linking errors, as JSON"
    );
    var checked = parser.flag(
        "emit-checked",
        help = "Load, link and check the program instead of compiling it, and print what the checks before sema report: the errors (linking, then `[__BuiltIn]` misuse, then visibility), then the warnings, rendered"
    );
    var model = parser.flag(
        "emit-model",
        help = "Load, link, check and build the program's sema model instead of compiling it, and print the model before any sema pass, as JSON"
    );
    var step = parser.option<ulong>(
        "emit-model-step",
        help = "With `--emit-model`: run the first N sema steps (one pass each, in the order the compiler runs them) and print the model after them",
        value_name = "N"
    );
    var steps = parser.flag(
        "emit-steps",
        help = "Load, link, check and build the program, run the sema passes, and print the name of each step run, one per line, instead of compiling"
    );
    var trace_channels = parser.multiple(
        "",
        "T",
        "Enable a trace channel. `time` prints how long each compile stage took; `passes` prints how long each sema pass took, summed over its runs; `cache` prints whether each unit's object came from the build cache; any other name is accepted and ignored",
        "CHAN"
    );
    var trace_all = parser.flag("Tall", help = "Enable all trace channels");
    var no_cache = parser.flag("no-cache", help = "Compile every unit without reading or writing the build cache");
    var cache_dir = parser.option(
        "cache",
        help = "Build cache directory (default: `$PEPPER_CACHE_DIR`, else `$CWD/.pep/cache`)",
        value_name = "DIR"
    );
    var verify_cache = parser.flag(
        "verify-cache",
        help = "Check the build cache: generate the code of every unit that hits anyway, and fail if it differs from the cached object's, or if skipping the hit units' bodies in sema changes another unit's code (also `PEPPER_CACHE_VERIFY=1`). For testing the compiler"
    );
    var no_verify_cache = parser.flag(
        "no-verify-cache", help = "Do not check the build cache, even with `PEPPER_CACHE_VERIFY` set"
    );
    var msvc = parser.flag("MSVC", help = "Use the MSVC linker. Not ported: always an error");
    # The internal options a build gives the children it starts.
    var compilation_unit_worker = parser.option(
        "compilation-unit-worker",
        help = "Internal: check the compilation units the build that started this child passes through DIR, and compile each one's object (`driver.compilation_unit_worker`). Builds start these themselves",
        value_name = "DIR"
    );
    var compile_part = parser.option(
        "compile-part",
        help = "Internal: compile parts of a program a build split into DIR, given by `--part`, instead of building (`driver.compile_part`). Builds start these themselves",
        value_name = "DIR"
    );
    var parts = parser.multiple(
        "part",
        help = "With `--compile-part`: a part to compile, by its number, and the object to write it to",
        value_name = "N=OBJECT"
    );
    var built_with = parser.option(
        "members",
        help = "Internal: the workspace members, a comma-separated list of package names, built with this one, whose features are unified with its. A build of several members starts each with it",
        value_name = "NAMES"
    );
    var member_dir = parser.option(
        "member",
        help = "Internal: with no file, build the project in DIR rather than the one around the current folder. A build of several members starts each with it",
        value_name = "DIR"
    );
    var print_members = parser.flag(
        "print-members",
        help = "Internal: print the name and folder of each workspace member `--all` or `-p` selects, a line each, instead of building. `pep-test` runs it"
    );
    if (!parser.parse(args)) {
        return 2;
    }
    if (compile_part.is_set) {
        return _compile_part(parser, Path(compile_part.value()), parts.values());
    }
    if (parts.is_set) {
        return parser.usage_error("'--part' needs '--compile-part'");
    }
    var paths = files.values();
    # A program is its entry file and what that imports; only `--test`
    # builds several files' tests together.
    if (paths.count > 1 and !test.is_set) {
        return parser.usage_error($"'{paths[1]}' is not compiled: only the entry file is; import it from '{paths[0]}'");
    }
    var path = paths.is_empty ? Optional<String>.Empty : Optional<String>.Value(paths[0]);
    # The workspace members `--all` and `-p` select: with no file, each is
    # built in a child of its own; with one, their features are unified.
    var members = Array<String>();
    # A child of a build of several members selects none again.
    if (!built_with.is_set
        and (print_members.is_set or !path.is_value() or all_members.is_set or member_names.is_set)) {
        var selected = driver.select_members(all_members.is_set, member_names.values());
        if (selected.is_err()) {
            _report(selected.error());
            return 1;
        }
        for (var member in selected.value()) {
            if (print_members.is_set) {
                print($"{member.name}\t{member.dir()}");
            }
            members.append(member.name);
        }
        if (print_members.is_set) {
            return 0;
        }
        if (!path.is_value() and !members.is_empty) {
            if (output.is_set and members.count > 1) {
                return parser.usage_error("'-o' names one output, and this builds several members; pick one with '-p'");
            }
            return driver.build_members(args, selected.value());
        }
    }
    if (built_with.is_set) {
        members = built_with.value().split(",");
    }
    if (debug_static.is_set and !debug.is_set) {
        return parser.usage_error("'--debug-static' needs '-g'");
    }
    if (!path.is_value()
        and (emit_ast.is_set
            or linked.is_set
            or checked.is_set
            or model.is_set
            or steps.is_set
            or ir.is_set
            or emit_static.is_set)) {
        return parser.usage_error("the --emit options need the program's entry file");
    }
    if (entry_function.is_set and test.is_set) {
        return parser.usage_error("'--entry' cannot be used with '--test'");
    }
    if (entry_function.is_set and library.is_set) {
        return parser.usage_error("'--entry' cannot be used with '--lib'");
    }
    if (test.is_set and library.is_set) {
        return parser.usage_error("'--test' cannot be used with '--lib'");
    }
    bool for_android = library.is_set and library.value() == driver.LibraryKind.Aar;
    bool for_apps = for_android
        or (library.is_set
            and (library.value() == driver.LibraryKind.Xcframework
                or library.value() == driver.LibraryKind.SwiftPackage));
    var app_kinds = "'--lib xcframework', '--lib swift-package' or '--lib aar'";
    if (for_apps and triple.is_set) {
        return parser.usage_error(
            $"'--target' cannot be used with {app_kinds}, which build for every iOS or Android target"
        );
    }
    if (for_apps
        and (emit_ast.is_set
            or linked.is_set
            or checked.is_set
            or model.is_set
            or steps.is_set
            or ir.is_set
            or emit_static.is_set)) {
        return parser.usage_error($"the --emit options cannot be used with {app_kinds}");
    }
    if (for_apps
        and library.value() == driver.LibraryKind.Xcframework
        and output.is_set
        and !output.value().ends_with(".xcframework")) {
        # The output is replaced whole, so it must be one.
        return parser.usage_error("the output of '--lib xcframework' must end in '.xcframework'");
    }
    if (bindings.is_set and (!library.is_set or for_apps)) {
        return parser.usage_error("'--bindings' needs '--lib static' or '--lib shared'");
    }
    if (bindings.is_set
        and bindings.value() == driver.BindingsKind.Java
        and library.value() != driver.LibraryKind.Shared) {
        # The JNI functions are compiled into the library Java loads.
        return parser.usage_error("'--bindings java' needs '--lib shared'");
    }
    if (verify_cache.is_set and no_verify_cache.is_set) {
        return parser.usage_error("'--verify-cache' cannot be used with '--no-verify-cache'");
    }
    if (level.is_set and level.value() > 3) {
        return parser.usage_error($"invalid value '{level.value()}' for '-O': expected 0, 1, 2 or 3");
    }
    var setup = link.Setup();
    setup.runtime = !no_runtime.is_set;
    setup.import_dirs.append_all(import_dirs.values());
    setup.forced_imports.append_all(imports.values());
    for (var define in defines.values()) {
        # `NAME` is `NAME=1`, as in C.
        var option = define.split_once("=");
        var name = option.is_value() ? option.value().0 : define;
        var value = option.is_value() ? option.value().1 : "1";
        if (!link.is_build_option_name(name)) {
            return parser.usage_error(
                $"invalid build option name '{name}' in '-D {define}'; {link.BUILD_OPTION_NAME_RULE}"
            );
        }
        setup.target.build_options[name] = value;
    }
    if (entry_function.is_set) {
        setup.target.build_options[link.ENTRY_BUILD_OPTION] = entry_function.value();
    }
    var traces = trace_channels.values();
    if (trace_all.is_set) {
        traces.append_all(TRACE_CHANNELS.split(" "));
    }
    var opt_level = level.is_set ? Optional<uint>.Value(level.value()) : Optional<uint>.Empty;
    # The platform to compile for, with the build options `-D` defined.
    if (triple.is_set) {
        var target = link.Target.parse(triple.value());
        if (target.is_err()) {
            _report(target.error());
            return 1;
        }
        var parsed = target.value();
        parsed.build_options = setup.target.build_options;
        setup.target = parsed;
    }
    for (var given in features.values()) {
        for (var name in given.split(",")) {
            if (!name.trim().is_empty) {
                setup.target.features.append(name.trim());
            }
        }
    }
    setup.target.default_features = !no_default_features.is_set;
    setup.target.members = members;
    if (build_script.is_set) {
        setup.target.build_script_root = Optional<Path>.Value(Path(build_script.value()));
    }
    # Without `-O`, `PEPPER_OPT_LEVEL` picks the level, as in pep-build, so a
    # whole test suite can run optimized.
    if (!opt_level.is_value()) {
        var from_environment = _env_opt_level();
        if (from_environment.is_err()) {
            File.stderr().write_all($"pepc: {from_environment.error()}\n");
            return 2;
        }
        opt_level = Optional<uint>.Value(from_environment.value());
    }
    # The runtime checks the code keeps: every one at `-O0`, else all but
    # those `--no-runtime-checks` removes.
    var runtime_checks = codegen.RuntimeChecks.all();
    if (without_checks.is_set) {
        var kept = codegen.RuntimeChecks.without(without_checks.value());
        if (!kept.is_value()) {
            return parser.usage_error(
                $"invalid value '{without_checks.value()}' for '--no-runtime-checks': expected overflow, divide, shift, bounds, null or all"
            );
        }
        if (opt_level.value() > 0) {
            runtime_checks = kept.value();
        }
    }
    # The CPU the `-m` options choose for the target, else clang's default.
    var cpu = codegen.Cpu.from_options(codegen.target_triple(setup.target), machine.values());
    if (cpu.is_err()) {
        _report(cpu.error());
        return 1;
    }
    # Link-time optimization: only when asked for, as it optimizes the whole
    # program again on every build, an edit's too.
    bool whole = false;
    if (lto.is_set) {
        if (lto.value() == _Lto.Full and opt_level.value() == 0) {
            _report("'--lto=full' needs optimization: add '-O'");
            return 1;
        }
        whole = lto.value() == _Lto.Full;
    }
    # In a project, the build takes what its `pep.toml` gives: with no file,
    # the entry and output; and `[build]`'s libraries.
    var project = driver.apply_project(
        path.is_value() ? Optional<Path>.Value(Path(path.value())) : Optional<Path>.Empty,
        setup.target,
        member_dir.is_set ? Optional<Path>.Value(Path(member_dir.value())) : Optional<Path>.Empty
    );
    if (project.is_err()) {
        _report(project.error());
        return 1;
    }
    var entry = project.value().entry;
    if (entry_function.is_set and !_declares_function(entry, entry_function.value())) {
        _report($"no function named '{entry_function.value()}' in '{entry}' to start the program in (from '--entry')");
        return 1;
    }
    if (test.is_set) {
        # A test build keeps the `[Test]` functions, loads `testing` into
        # every file, and adds the `main` that runs them.
        setup.target.build_options[link.TEST_BUILD_OPTION] = "1";
        # The test `main` lists the `[Test]`s a feature's build option keeps;
        # loading the program turns the features on again and reports errors.
        link.Packages(entry, setup.target).turn_on_features();
        if (!setup.forced_imports.contains(driver.TESTING_MODULE)) {
            setup.forced_imports.append(driver.TESTING_MODULE);
        }
        if (paths.count > 1) {
            var test_files = Array<Path>();
            for (var p in paths) {
                test_files.append(Path(p));
            }
            var made = driver.test_program(test_files, setup.target);
            if (made.is_err()) {
                _report(made.error());
                return 1;
            }
            var (generated, sources) = made.value();
            entry = generated;
            setup.sources = sources;
        } else {
            var read = File.read_to_string(entry);
            if (read.is_err()) {
                File.stderr().write_all($"cannot read {entry}: {read.error().message}\n");
                return 1;
            }
            setup.sources[link.path_key(entry)] = driver.add_test_main(entry, read.value(), setup.target);
        }
    }
    # Where a build writes: `-o`, else named for the entry file or the
    # project, and its intermediate files (`--build`).
    var cwd = process.working_directory();
    var here = cwd.is_ok() ? cwd.value() : Path(".");
    var stem = entry.file_stem();
    var work = project.value().dir.is_value() ? project.value().dir.value() : here;
    var kind = library.is_set ?
        Optional<driver.LibraryKind>.Value(library.value()) :
        Optional<driver.LibraryKind>.Empty;
    # A Windows executable needs its extension to run, as a project's gets.
    var suffix = setup.target.os == "windows" ? ".exe" : "";
    var out = here.join(Path((stem.is_value() ? stem.value() : "main") + suffix));
    if (output.is_set) {
        out = Path(output.value());
    } else if (kind.is_value()) {
        # A library is named for the package, else the entry file,
        # as the target names libraries (`libmain.a`).
        var named = project.value().name.is_empty ? (stem.is_value() ? stem.value() : "main") : project.value().name;
        out = work.join(Path(driver.library_file_name(kind.value(), named, setup.target)));
    } else if (project.value().output.is_value()) {
        out = project.value().output.value();
    }
    var build_folder = build_dir.is_set ? Path(build_dir.value()) : work.join(Path(".pep")).join(Path("build"));
    if (for_apps) {
        # Each iOS target's static library, or each Android ABI's shared
        # one, built by this compiler, then packaged (`driver/xcframework.pep`,
        # `driver/aar.pep`).
        var executable = process.executable_path();
        if (executable.is_err()) {
            _report($"cannot find this program to build each target: {executable.error().message}");
            return 1;
        }
        var named = out.file_stem();
        if (for_android and (!named.is_value() or !driver.is_module_name(named.value()))) {
            _report(
                $"'{out}' does not name an Android library: it is named for its output, which takes letters, digits and '_' (pass '-o name.aar')"
            );
            return 1;
        }
        if (for_android) {
            var made = driver.build_aar(executable.value(), args, out, named.value(), build_folder.join(Path("aar")));
            if (made.is_err()) {
                if (!made.error().is_empty) {
                    _report(made.error());
                }
                return 1;
            }
            return 0;
        }
        if (!named.is_value() or !driver.is_module_name(named.value())) {
            _report(
                $"'{out}' does not name a Swift module: a library for iOS apps is named for its output, which takes letters, digits and '_' (pass '-o Name.xcframework')"
            );
            return 1;
        }
        var built = driver.build_xcframework(
            executable.value(),
            args,
            out,
            named.value(),
            build_folder.join(Path("xcframework")),
            library.value() == driver.LibraryKind.SwiftPackage
        );
        if (built.is_err()) {
            if (!built.error().is_empty) {
                _report(built.error());
            }
            return 1;
        }
        return 0;
    }
    if (emit_ast.is_set) {
        var source = File.read_to_string(path.value());
        if (source.is_err()) {
            File.stderr().write_all($"error: cannot read '{path.value()}'\n");
            return 1;
        }
        var module = parse.parse(source.value());
        if (module.is_err()) {
            var error = module.error();
            File.stderr().write_all($"{path.value()}:{error.span.start}: error: {error.message}\n");
            return 1;
        }
        if (emit_ast.value() == _AstFormat.Json) {
            print(module.value().to_json().to_string());
        } else {
            # The text ends with a newline, which `print` adds.
            var text = ast.module_text(module.value());
            print(text.ends_with("\n") ? text.substr_bytes(0, text.size - 1) : text);
        }
        return 0;
    }
    if (!(linked.is_set or checked.is_set or model.is_set or steps.is_set)) {
        # Debug builds keep every check.
        if (without_checks.is_set and opt_level.value() == 0) {
            var kept = codegen.RuntimeChecks.without(without_checks.value()).value();
            if (!(kept.overflow and kept.divide and kept.shift and kept.bounds and kept.null)) {
                File.stderr().write_all("warning: '--no-runtime-checks' has no effect at -O0\n");
            }
        }
        if (msvc.is_set) {
            _report("the MSVC linker path is not ported");
            return 1;
        }
    }
    var sysroot_dir = driver.effective_sysroot(
        setup.target, sysroot.is_set ? Optional<Path>.Value(Path(sysroot.value())) : Optional<Path>.Empty
    );
    # A build script's build has what the build that runs it fetched.
    if (!(linked.is_set or checked.is_set or model.is_set or steps.is_set or ir.is_set or build_script.is_set)) {
        # A project builds with what pep.lock lists: fetch what is missing.
        var fetched = driver.fetch_dependencies(
            entry,
            locked = locked.is_set or frozen.is_set or os.environment_flag("PEPPER_LOCKED"),
            offline = offline.is_set or frozen.is_set or os.environment_flag("PEPPER_OFFLINE"),
            target = setup.target
        );
        if (fetched.is_err()) {
            File.stderr().write_all(fetched.error() + "\n");
            return 1;
        }
    }
    # The packages' build scripts run before the program loads: it imports
    # the modules they generate, and the build options they define select
    # its code.
    setup.build_dir = Optional<Path>.Value(build_folder);
    var inputs = driver.ScriptInputs();
    inputs.target = setup.target;
    inputs.build_dir = build_folder;
    inputs.opt_level = opt_level.value();
    inputs.sysroot = sysroot_dir;
    inputs.refuse = no_build_scripts.is_set or os.environment_flag("PEPPER_NO_BUILD_SCRIPTS");
    # The program's cache, even with `--no-cache`: a script's stamp needs its
    # program's record.
    inputs.cache = cache_dir.is_set ? incremental.Cache(Path(cache_dir.value())) : incremental.default_cache(work);
    var scripts = driver.run_build_scripts(entry, inputs);
    if (scripts.is_err()) {
        _report(scripts.error());
        return 1;
    }
    for (var (name, value) in scripts.value().build_options) {
        setup.target.build_options[name] = value;
    }
    # A build links the bodies of only the files it checks
    # (`driver.build`).
    setup.defer_bodies = !(ir.is_set
        or model.is_set
        or steps.is_set
        or linked.is_set
        or checked.is_set
        or emit_static.is_set);
    # A rebuild's first compilation unit worker loads the program while this
    # process does (`driver.start_compilation_unit_worker`).
    var early_worker = Optional<process.Child>.Empty;
    if (setup.defer_bodies and !compilation_unit_worker.is_set and !no_cache.is_set and !debug.is_set) {
        var worker_args = Array<String>();
        for (var k in 1..args.count) {
            worker_args.append(args[k]);
        }
        early_worker = driver.start_compilation_unit_worker(worker_args, build_folder);
    }
    var program = link.load_program(entry, setup);
    if (program.is_err()) {
        _report(program.error());
        return 1;
    }
    if (emit_static.is_set) {
        # The copies go into `-o`, else `<stem>.static`.
        var stem = entry.file_stem();
        var out_dir = Path(output.is_set ? output.value() : $"{stem.is_value() ? stem.value() : "main"}.static");
        var written = driver.emit_static(program.value(), entry, out_dir, emit_static.value() == _StaticMode.Keep);
        if (written.is_err()) {
            _report(written.error());
            return 1;
        }
    } else if (ir.is_set) {
        # The whole program's IR, optimized at the `-O` level, in
        # `<build>/<name>.ll`.
        var built = sema.merge(program.value());
        if (built.is_err()) {
            File.stderr().write_all($"{built.error()}\n");
            return 1;
        }
        var state = sema.PassState(program.value().target);
        state.sources = program.value().sources();
        state.lazy_methods = true;
        if (traces.contains("passes")) {
            state.pass_times = Optional<sema.PassTimes>.Value(sema.PassTimes());
        }
        var ran = sema.run_steps_with(built.value(), state, 0xffffffffffffffff);
        if (ran.is_err()) {
            File.stderr().write_all(render_all([ran.error()], program.value().sources()) + "\n");
            return 1;
        }
        if (state.pass_times.is_value()) {
            File.stderr().write_all(state.pass_times.value().report());
        }
        var namespaces = Array<String>();
        for (var f in program.value().files) {
            namespaces.append(f.namespace);
        }
        var module_name = out.file_stem();
        var name = module_name.is_value() ? module_name.value() : "main";
        var generated = codegen.generate_ir(
            built.value(),
            state,
            namespaces,
            name,
            Optional<codegen.Cpu>.Value(cpu.value()),
            debug.is_set,
            opt_level.value(),
            frame_pointers.is_set,
            runtime_checks,
            debug.is_set ? driver.gdb_printers(program.value()) : "",
            library.is_set
        );
        if (generated.is_err()) {
            File.stderr().write_all(render_all([generated.error()], program.value().sources()) + "\n");
            return 1;
        }
        Directory.create_all(build_folder);
        var ll = build_folder.join(Path($"{name}.ll"));
        var written = File.write_text(ll, generated.value());
        if (written.is_err()) {
            _report($"cannot write {ll}: {written.error().message}");
            return 1;
        }
    } else if (model.is_set or steps.is_set) {
        var built = sema.merge(program.value());
        if (built.is_err()) {
            File.stderr().write_all($"{built.error()}\n");
            return 1;
        }
        # `--emit-steps` runs every step, or the first `--emit-model-step`.
        if (steps.is_set or step.is_set) {
            var state = sema.PassState(program.value().target);
            state.sources = program.value().sources();
            var limit = step.is_set ? step.value() : 0xffffffffffffffff;
            var ran = sema.run_steps_with(built.value(), state, limit);
            if (ran.is_err()) {
                File.stderr().write_all(render_all([ran.error()], program.value().sources()) + "\n");
                return 1;
            }
            if (steps.is_set) {
                print("\n".join(state.step_names));
                return 0;
            }
        }
        print(sema.model_json(built.value()));
    } else if (linked.is_set) {
        print(program.value().to_json().to_string());
    } else if (checked.is_set) {
        print(program.value().check_report());
    } else {
        var options = driver.BuildOptions(out, build_folder);
        options.opt_level = opt_level.value();
        options.frame_pointers = frame_pointers.is_set;
        options.cpu = Optional<codegen.Cpu>.Value(cpu.value());
        options.lto = whole;
        options.library = kind;
        if (bindings.is_set) {
            options.bindings = Optional<driver.BindingsKind>.Value(bindings.value());
        }
        options.debug = debug.is_set;
        options.entry = Optional<Path>.Value(entry);
        options.debug_static_expanded = debug_static.is_set and debug_static.value() == _DebugStatic.Expanded;
        options.runtime_checks = runtime_checks;
        if (traces.contains("passes")) {
            options.pass_times = Optional<sema.PassTimes>.Value(sema.PassTimes());
        }
        var linked_libraries = libraries.values();
        for (var library in project.value().libraries) {
            if (!linked_libraries.contains(library)) {
                linked_libraries.append(library);
            }
        }
        options.libraries = linked_libraries;
        options.library_dirs = library_dirs.values();
        options.sysroot = sysroot_dir;
        # A cached unit's sema is skipped, so its expansions would not be
        # written for `--debug-static=expanded`.
        if (!no_cache.is_set and !options.debug_static_expanded) {
            options.cache = Optional<incremental.Cache>.Value(inputs.cache);
        }
        # `--verify-cache`, or `PEPPER_CACHE_VERIFY` set to anything but
        # empty or `0`, unless `--no-verify-cache`.
        bool verifying = verify_cache.is_set
            or (!no_verify_cache.is_set and os.environment_flag("PEPPER_CACHE_VERIFY"));
        options.verify_cutoff = verifying;
        options.trace_time = traces.contains("time");
        options.trace_cache = traces.contains("cache");
        if (compilation_unit_worker.is_set) {
            return driver.compilation_unit_worker(program.value(), options, Path(compilation_unit_worker.value()));
        }
        for (var k in 1..args.count) {
            options.worker_args.append(args[k]);
        }
        options.early_worker = early_worker;
        for (var library in scripts.value().libraries) {
            if (!options.libraries.contains(library)) {
                options.libraries.append(library);
            }
        }
        options.library_dirs.append_all(scripts.value().library_dirs);
        options.objects = scripts.value().objects;
        var made = driver.build(program.value(), options);
        if (made.is_err()) {
            # Empty: printed already (a syntax error read late).
            if (!made.error().is_empty) {
                _report(made.error());
            }
            return 1;
        }
        if (verifying and options.cache.is_value()) {
            # The program again, as the build loaded it.
            var reloaded = link.load_program(entry, setup);
            if (reloaded.is_err()) {
                _report(reloaded.error());
                return 1;
            }
            var verified = driver.verify_cache(reloaded.value(), options);
            if (verified.is_err()) {
                _report(verified.error());
                return 1;
            }
        }
    }
    return 0;
}

## The level `PEPPER_OPT_LEVEL` names (`0` to `3`), or 0 when it is unset
## or empty.
_env_opt_level(): Result<uint, String> {
    var value = os.environment("PEPPER_OPT_LEVEL");
    if (!value.is_value() or value.value().is_empty) {
        return Result<uint, String>.ok(0);
    }
    var level = uint.parse(value.value());
    if (!level.is_value() or level.value() > 3) {
        return Result<uint, String>.err($"PEPPER_OPT_LEVEL is '{value.value()}'; expected 0, 1, 2 or 3");
    }
    return Result<uint, String>.ok(level.value());
}

## The release this compiler belongs to: `scripts/set-version.sh` sets it.
version(): String {
    return "0.12.0-dev";
}

## The channels `-T` names, which `--Tall` enables (`pep-doc check` reads
## them, for `docs/src/tools/pep-build.md`).
const TRACE_CHANNELS = "time passes cache";

# Whether the file `path` declares a top-level function `name`, for
# `--entry`; true when it cannot be read or parsed, which loading reports.
_declares_function(path: Path, name: String): bool {
    var source = File.read_to_string(path);
    if (source.is_err()) {
        return true;
    }
    var module = parse.parse(source.value());
    if (module.is_err()) {
        return true;
    }
    for (var declaration in module.value().declarations) {
        if (declaration is Function(function)) {
            if (function.name == name) {
                return true;
            }
        }
    }
    return false;
}

# Prints `message` on standard error as an error: with `error:` unless it is
# a rendered diagnostic that says so already.
_report(message: String) {
    var text = message.contains("error:") ? message : $"error: {message}";
    File.stderr().write_all(text.ends_with("\n") ? text : text + "\n");
}

# The parts of a split build `--compile-part dir` names with `--part
# N=OBJECT` (`driver/parts.pep`): compiles them.
_compile_part(parser: cli.Parser, dir: Path, parts: String[]): int {
    if (parts.is_empty) {
        return parser.usage_error("'--compile-part' needs a '--part'");
    }
    var jobs = Array<driver.PartJob>();
    for (var given in parts) {
        var split = given.split_once("=");
        var number = split.is_value() ? uint.parse(split.value().0) : Optional<uint>.Empty;
        if (!number.is_value()) {
            return parser.usage_error($"invalid value '{given}' for '--part': expected N=OBJECT");
        }
        jobs.append(driver.PartJob(number.value(), Path(split.value().1)));
    }
    var compiled = driver.compile_part(dir, jobs);
    if (compiled.is_err()) {
        _report(compiled.error());
        return 1;
    }
    return 0;
}

# `--lto`'s modes.
enum _Lto {
    Full,
    Off,
}

# `--emit-ast`'s formats.
enum _AstFormat {
    Text,
    Json,
}

# `--emit-static`'s modes: the expansions alone, or each block kept above
# its expansion.
enum _StaticMode {
    Expand,
    Keep,
}

# `--debug-static`'s views of a `static` block.
enum _DebugStatic {
    Source,
    Expanded,
}
