# pep-run: builds a program and runs it straight away, like
# `python script.py`; `pepper run` runs it.
#
#     pep-run hello.pep                 # build hello.pep, then run it
#     pep-run -O2 args.pep a b          # build options first; a b go to main
#     pep-run -- a b                    # the project pep.toml describes
#     pep-run --entry bench tool.pep    # start in bench(), not main()
#
# The arguments before the entry file (the first one ending in `.pep`) are
# `pep-build`'s options; everything after it, or after `--`, goes to the
# program. With no file it builds the project whose pep.toml is in the
# current folder or above, as `pep-build` does.
#
# The executable goes in `<Pepper home>/run/<key>/`, the key a hash of the
# current folder and the build options, with the build cache in
# `PEPPER_CACHE_DIR`, else `<Pepper home>/cache`, shared by every run. A run
# with nothing changed finds the program up to date and starts it at once.
# The linker writes the executable to a temporary file and renames it into place,
# so two runs of one script at the same time never see half of one. The
# program then takes this process's place (on Windows, pep-run waits for
# it) in the folder pep-run started in, with its standard streams, and its
# exit status is pep-run's.
#
# Build it from the repository root:
#
#     pep-build tools/pep-run/main.pep -o target/bin/pep-run

import digest;
import [Directory, File, Path] from io;
import os;
import process;
import toolchain;

# The release this tool belongs to. `pep-doc check` keeps it equal to the
# version in VERSION.
version(): String {
    return "0.9.4";
}

const HELP = "Builds a Pepper program and runs it.\n\nUsage: pep-run [BUILD OPTIONS] [<entry.pep>] [ARGUMENTS]...\n       pep-run [BUILD OPTIONS] -- [ARGUMENTS]...\n\nThe arguments before the entry file (the first ending in .pep) are pep-build's\noptions, such as -O2, -D NAME and -I DIR; those after it, or after --, go to\nthe program. With no file, runs the project whose pep.toml is in the current\nfolder or above. --entry NAME starts the program in the function NAME instead\nof main. The options that choose what pep-build writes (-o, --lib,\n--test, --target and the --emit options) are not taken.\n\nOptions:\n      --entry <NAME>  Start the program in the function NAME instead of main\n  -h, --help          Print help\n  -V, --version       Print version\n";

main(args: String[]): int {
    var build_options = Array<String>();
    var entry = "";
    var program_arguments = Array<String>();
    ulong index = 1;
    while (index < args.count) {
        var argument = args[index];
        index += 1;
        if (argument == "--") {
            break;
        }
        if (argument == "-h" or argument == "--help") {
            File.stdout().write_all(HELP);
            return 0;
        }
        if (argument == "-V" or argument == "--version") {
            File.stdout().write_all($"pep-run {version()}\n");
            return 0;
        }
        # Its value is a function's name, never the entry file.
        if (argument == "--entry" and index < args.count) {
            build_options.append(argument);
            build_options.append(args[index]);
            index += 1;
            continue;
        }
        if (argument.ends_with(".pep") and !argument.starts_with("-")) {
            entry = argument;
            break;
        }
        var refused = refused_option(argument);
        if (!refused.is_empty) {
            File.stderr().write_all(
                $"pep-run: error: '{refused}' is not taken: pep-run runs the executable it builds\n"
            );
            return 2;
        }
        build_options.append(argument);
    }
    while (index < args.count) {
        program_arguments.append(args[index]);
        index += 1;
    }

    var compiler = process.find_companion("pep-build");
    if (compiler.is_empty()) {
        return fail("cannot find pep-build next to pep-run or on the PATH");
    }
    var here = Directory.current();
    if (here.is_err()) {
        return fail($"cannot tell the current directory: {here.error().message}");
    }
    var home = toolchain.find_home().root;
    var key_text = here.value().to_string();
    for (var option in build_options) {
        key_text = key_text + "\n" + option;
    }
    key_text = key_text + "\n" + entry;
    var key = digest.to_hex(digest.blake3(key_text)).substr_bytes(0, 16);
    var folder = home.join("run").join(key);
    var made = Directory.create_all(folder);
    if (made.is_err()) {
        return fail($"cannot create '{folder}': {made.error().message}");
    }
    var stem = entry.is_empty ? "main" : Path(entry).file_stem().value_or("main");
    var executable = folder.join(stem + toolchain.executable_suffix());

    var build = process.Command(compiler.value().to_string());
    if (!entry.is_empty) {
        build = build.argument(entry);
    }
    build = build
        .arguments(build_options)
        .argument("-o")
        .argument(executable.to_string())
        .argument("--build")
        .argument(folder.join("build").to_string());
    if (cache_dir_unset()) {
        build = build.argument("--cache").argument(home.join("cache").to_string());
    }
    # pep-build reports errors and warnings itself, as `pepper build` does.
    var built = build.stdin(process.Stream.Inherit).stdout(process.Stream.Inherit).stderr(process.Stream.Inherit).run();
    if (built.is_err()) {
        return fail($"cannot run pep-build: {built.error().message}");
    }
    if (!built.value().status.success()) {
        var code = built.value().status.code().value_or(1);
        return code == 0 ? 1 : code;
    }

    var error = process.Command(executable.to_string()).arguments(program_arguments).exec();
    return fail($"cannot run '{executable}': {error.message}");
}

# The spelling of `argument` when it is a build option pep-run does not
# take, because it changes what pep-build writes; else empty.
refused_option(argument: String): String {
    if (argument.starts_with("--emit") or argument.starts_with("-o")) {
        return argument;
    }
    for (var option in ["--lib", "--test", "--target"]) {
        if (argument == option or argument.starts_with(option + "=")) {
            return option;
        }
    }
    return "";
}

# Whether `PEPPER_CACHE_DIR` leaves the cache folder to pep-run.
cache_dir_unset(): bool {
    var named = os.environment("PEPPER_CACHE_DIR");
    return named.is_empty() or named.value().is_empty;
}

fail(message: String): int {
    File.stderr().write_all($"pep-run: error: {message}\n");
    return 1;
}
