# pep-doc: builds the Pepper book and its standard library reference, run
# as `pepper doc`. `HELP` is its `--help`, listing each command and option;
# the book's tools/pep-doc.md documents them, and `pep-doc check` checks
# that it does (`checks.pep`).
#
# It works on the Pepper checkout that holds the current folder. mdBook
# must be on PATH (`cargo install mdbook --locked`).
#
# Build it from the repository root, next to the compiler:
#
#     target/release/pep-build -I tools tools/pep-doc/main.pep -o target/release/pep-doc

import [Directory, File, Path] from io;
import process;
import "book";
import "checks";
import "reference";
import "site";

# The release this tool belongs to, as the other Pepper tools give it.
version(): String {
    return "0.4.0-dev";
}

# What `pep-doc --help` prints.
const HELP = "Builds the Pepper book and its standard library reference.

usage: pep-doc [<command>] [options]

Commands:
  reference   regenerate docs/src/reference/ from the runtime's doc comments
  check       fail if the reference is stale, a chapter is broken, an API or tool option is undocumented, or a tool's version differs from VERSION
  build       regenerate the reference and render the book (the default)
  serve       regenerate the reference and serve the book locally
  help        show this help

Options:
  --version <VERSION>  with build: the version to build, X.Y.Z or dev (default: dev)
  --site <DIR>         with build: the site folder (default: target/docs-site)
  --tools <DIR>        with check: the folder of the built tools (default:
                       target/pepper-tests/bin, else the release build's, else
                       the debug build's)
  -h, --help           show this help
  -V, --version        with no command: show pep-doc's version
";

main(args: String[]): int {
    var arguments = Array<String>();
    for (var i in 1..args.count) {
        arguments.append(args[i]);
    }
    var ran = _run(arguments);
    if (ran.is_err()) {
        File.stderr().write_all($"error: {ran.error().message}\n");
        return 1;
    }
    return 0;
}

_run(args: String[]): Result<void> {
    var command = args.is_empty ? "build" : args[0];
    if (command == "help" or command == "--help" or command == "-h") {
        File.stdout().write_all(HELP);
        return Result<void>.ok();
    }
    if (command == "--version" or command == "-V") {
        File.stdout().write_all($"pep-doc {version()}\n");
        return Result<void>.ok();
    }
    var root = _repository_root()?;
    if (command == "reference") {
        for (var path in _regenerate(root)?) {
            File.stdout().write_all($"updated {_relative(root, path)}\n");
        }
        return Result<void>.ok();
    }
    if (command == "check") {
        return _check(root, _option(args, "--tools"));
    }
    if (command == "build") {
        return _build(root, _option(args, "--version"), _option(args, "--site"));
    }
    if (command == "serve") {
        _regenerate(root)?;
        return _mdbook(["serve", "docs", "--open"], root);
    }
    return Result<void>.Err($"unknown command '{command}': expected reference, check, build, serve, or help");
}

# The value after option `name` in `args`.
_option(args: String[], name: String): String? {
    for (var i in 0..args.count) {
        if (args[i] == name and i + 1 < args.count) {
            return Optional<String>.Value(args[i + 1]);
        }
    }
    return Optional<String>.Empty;
}

# The root of the Pepper checkout that holds the current folder: the
# nearest folder up from it with `runtime/` and the book's
# `docs/src/SUMMARY.md`.
_repository_root(): Result<Path> {
    var current = Directory.current();
    if (current.is_err()) {
        return Result<Path>.Err($"cannot read the current folder: {current.error().message}");
    }
    Path? folder = Optional<Path>.Value(current.value());
    while (folder.is_value()) {
        var candidate = folder.value();
        if (candidate.join("runtime").is_directory()
            and candidate.join("docs").join("src").join("SUMMARY.md").is_file()) {
            return Result<Path>.ok(candidate);
        }
        folder = candidate.parent();
    }
    return Result<Path>.Err(
        "run pep-doc inside a Pepper checkout: no folder up from here holds runtime/ and docs/src/SUMMARY.md"
    );
}

# `path` from `root`, with `/` separators.
_relative(root: Path, path: Path): String {
    var text = path.to_string();
    var prefix = root.to_string() + Path.separator();
    if (text.starts_with(prefix)) {
        text = text.substr_bytes(prefix.size, text.size - prefix.size);
    }
    return text.replace("\\", "/");
}

# A text file with Windows line ends (`\r\n`) read as `\n`, as a checkout
# with `core.autocrlf` may have written it; none when it cannot be read.
_read_normalized(path: Path): String? {
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(text.value().replace("\r\n", "\n"));
}

_regenerate(root: Path): Result<Path[]> {
    var pages = generate(root.join("runtime"))?;
    return write(root.join("docs"), pages);
}

_check(root: Path, tools: String?): Result<void> {
    var pages = generate(root.join("runtime"))?;
    var dir = root.join("docs").join("src").join("reference");
    var stale = Array<String>();
    for (var page in pages) {
        var current = _read_normalized(dir.join(page.file));
        if (current.is_empty() or current.value() != page.markdown) {
            stale.append($"docs/src/reference/{page.file}");
        }
    }
    var summary = _read_normalized(root.join("docs").join("src").join("SUMMARY.md"));
    if (summary.is_empty()) {
        return Result<void>.Err("cannot read docs/src/SUMMARY.md");
    }
    if (update_summary(summary.value(), pages)? != summary.value()) {
        stale.append("docs/src/SUMMARY.md");
    }
    var broken = lint(root.join("docs").join("src"))?;
    _report(broken);
    var undocumented = undocumented_declarations(root)?;
    _report(undocumented);
    var unlisted = undocumented_tool_options(root, tools_dir(root, tools), HELP)?;
    _report(unlisted);
    var versions = stale_versions(root)?;
    _report(versions);
    var errors = Array<String>();
    if (!undocumented.is_empty) {
        errors.append($"{undocumented.count} public runtime declaration(s) without a doc comment");
    }
    if (!unlisted.is_empty) {
        errors.append($"{unlisted.count} tool option(s) missing from their pages");
    }
    if (!broken.is_empty) {
        errors.append($"{broken.count} problem(s) in the book's chapters");
    }
    if (!versions.is_empty) {
        errors.append($"{versions.count} tool version(s) differ from VERSION");
    }
    if (!stale.is_empty) {
        errors.append($"the standard library reference is out of date: {", ".join(stale)}\nrun `{REGENERATE}`");
    }
    if (errors.is_empty) {
        return Result<void>.ok();
    }
    return Result<void>.Err("\n".join(errors));
}

# Prints each of `problems` on standard error.
_report(problems: String[]) {
    for (var problem in problems) {
        File.stderr().write_all(problem + "\n");
    }
}

_build(root: Path, requested: String?, site_option: String?): Result<void> {
    String name = DEV;
    if (requested.is_value() and requested.value() != DEV) {
        name = parse_version(requested.value())?.to_string();
    }
    var site_dir = site_option.is_value() ? Path(site_option.value()) : root.join("target").join("docs-site");
    var created = Directory.create_all(site_dir);
    if (created.is_err()) {
        return Result<void>.Err($"cannot create {site_dir.to_string()}: {created.error().message}");
    }
    var absolute = site_dir.canonicalize();
    if (absolute.is_err()) {
        return Result<void>.Err($"cannot find {site_dir.to_string()}: {absolute.error().message}");
    }
    var site = absolute.value();
    _regenerate(root)?;
    var out = site.join(name);
    Directory.remove_all(out);
    _mdbook(["build", "docs", "--dest-dir", out.to_string()], root)?;
    write_index(site)?;
    File.stdout().write_all($"built docs {name} into {out.to_string()}\n");
    return Result<void>.ok();
}

# Runs mdBook with `arguments` in the folder `root`.
_mdbook(arguments: String[], root: Path): Result<void> {
    var ran = process
        .Command("mdbook")
        .arguments(arguments)
        .working_directory(root)
        .stdout(process.Stream.Inherit)
        .stderr(process.Stream.Inherit)
        .run();
    if (ran.is_err()) {
        return Result<void>.Err(
            $"cannot run mdbook ({ran.error().message}); install it with `cargo install mdbook --locked`"
        );
    }
    if (!ran.value().status.success()) {
        return Result<void>.Err($"mdbook {" ".join(arguments)} failed ({ran.value().status.to_string()})");
    }
    return Result<void>.ok();
}
