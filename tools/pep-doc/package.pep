# `pep-doc package`: the reference of a package, from its own `pep.toml`
# and sources, as an mdBook in its `.pep/doc/`.
#
# A page per source file with public declarations (as the standard
# library's reference has, through `reference.pep`), titled by the module
# it is (`geometry.solids`) or its path, and a front page with the
# package's description, its pages, its `[features]` and links to its
# dependencies' docs. A declaration a feature gates says which feature
# turns it on.

import [check_documented, file_doc] from compiler.doc;
import [Directory, File, Path] from io;
import [Dependency, Manifest, find_manifest, load_manifest] from compiler.link;
import toml;
import [package_string] from toolchain;
import "reference";

# The command whose pages these are, named in each page's header.
const COMMAND = "pep-doc package";

# The manifest of the package holding the current folder: the nearest
# `pep.toml` up from it.
export current_package(): Result<Manifest> {
    var current = Directory.current();
    if (current.is_err()) {
        return Result<Manifest>.Err($"cannot read the current folder: {current.error().message}");
    }
    var path = find_manifest(current.value());
    if (path.is_empty()) {
        return Result<Manifest>.Err("run pep-doc package inside a package: no folder up from here holds a pep.toml");
    }
    var loaded = load_manifest(path.value(), Array<Path>());
    if (loaded.is_err()) {
        return Result<Manifest>.Err(loaded.error());
    }
    if (loaded.value().name.is_empty) {
        return Result<Manifest>.Err(
            $"{path.value().to_string()} has no [package]: run pep-doc package in one of the workspace's packages"
        );
    }
    return Result<Manifest>.ok(loaded.value());
}

# `[package]`'s text `key` (`version`), or empty.
export manifest_string(manifest: Manifest, key: String): String {
    var root = toml.parse(manifest.text);
    return root.is_ok() ? package_string(root.value(), key) : "";
}

# Each feature of the package, with the build option that turning it on
# defines: `("http_tls", "tls")`.
export feature_options(manifest: Manifest): (String, String)[] {
    var out = Array<(String, String)>();
    for (var feature in manifest.features) {
        out.append(($"{manifest.name}_{feature.name}", feature.name));
    }
    return out;
}

# The `.pep` files of the package at `root` that the reference documents,
# a module's `module.pep` before its other files.
export package_files(root: Path): Result<String[]> {
    var files = Array<String>();
    pep_files(root, "", files)?;
    files.sort((a, b) => _sort_key(a).compare(_sort_key(b)));
    return Result<String[]>.ok(files);
}

# `file` with a trailing `module.pep` dropped, so it sorts before the
# other files of its folder.
_sort_key(file: String): String {
    return file.ends_with("module.pep") and (file.size == 10 or file.ends_with("/module.pep")) ?
        file.substr_bytes(0, file.size - 10) :
        file;
}

# A page's title: the module a `module.pep` is (`geometry`,
# `geometry.solids`), else the file's path.
export package_title(name: String, file: String): String {
    if (file == "module.pep") {
        return name;
    }
    if (file.ends_with("/module.pep")) {
        return $"{name}.{file.substr_bytes(0, file.size - 11).replace("/", ".")}";
    }
    return file;
}

# The pages of the package `manifest` describes, in reading order. Files
# with nothing public and no introduction get no page.
export package_pages(manifest: Manifest): Result<Page[]> {
    var root = manifest.dir();
    var features = feature_options(manifest);
    var out = Array<Page>();
    for (var file in package_files(root)?) {
        var path = root.join(file);
        var read = File.read_to_string(path);
        if (read.is_err()) {
            return Result<Page[]>.Err($"cannot read {path.to_string()}: {read.error().message}");
        }
        var source = read.value();
        var module = parse_file(file, source)?;
        var body = "".join([reexports(module, file, manifest.name), page_body(module, source, features)]);
        var intro = file_doc(source);
        if (body.is_empty and intro.is_empty()) {
            continue;
        }
        var title = package_title(manifest.name, file);
        out.append(Page(page_file(file), title, page_markdown(file, COMMAND, title, intro, body)));
    }
    return Result<Page[]>.ok(out);
}

# Where the docs of `dependency` are: the GitHub Pages site the package
# template's CI publishes, for a GitHub repository; its repository, for
# another host; nothing for a folder.
export dependency_docs(dependency: Dependency): String? {
    if (dependency.host.is_empty()) {
        return Optional<String>.Empty;
    }
    var host = dependency.host.value();
    if (host.key() == "github") {
        var parts = dependency.location.split("/");
        if (parts.count == 2) {
            return Optional<String>.Value($"https://{parts[0].lower()}.github.io/{parts[1]}/");
        }
    }
    return Optional<String>.Value($"https://{host.domain()}/{dependency.location}");
}

# The front page: the package's name, version and description, then its
# pages, features and dependencies.
export package_index(manifest: Manifest, pages: Page[]): String {
    var version = manifest_string(manifest, "version");
    var out = StringBuilder();
    out.append($"<!-- Generated from pep.toml by `{COMMAND}`. Do not edit. -->\n\n");
    out.append(version.is_empty ? $"# {manifest.name}\n" : $"# {manifest.name} {version}\n");
    var description = manifest_string(manifest, "description");
    if (!description.is_empty) {
        out.append($"\n{description}\n");
    }
    if (!pages.is_empty) {
        out.append("\n## Pages\n\n");
        for (var page in pages) {
            var sentence = first_sentence(page.markdown);
            out.append(
                sentence.is_empty ? $"- [{page.title}]({page.file})\n" : $"- [{page.title}]({page.file}): {sentence}\n"
            );
        }
    }
    if (!manifest.features.is_empty) {
        out.append("\n## Features\n\n");
        out.append(
            $"A feature that a build turns on defines the build option `{manifest.name}_<feature>` (see [Features](https://pepper-lang.dev/dev/tools/projects.html#features)).\n\n"
        );
        for (var feature in manifest.features) {
            var enables = Array<String>();
            for (var item in feature.enables) {
                enables.append($"`{item}`");
            }
            var turns_on = enables.is_empty ? "turns on nothing else" : $"turns on {", ".join(enables)}";
            out.append($"- `{feature.name}`: {turns_on}\n");
        }
    }
    if (!manifest.dependencies.is_empty) {
        out.append("\n## Dependencies\n\n");
        for (var dependency in manifest.dependencies) {
            var docs = dependency_docs(dependency);
            var name = docs.is_value() ? $"[`{dependency.name}`]({docs.value()})" : $"`{dependency.name}`";
            var notes = Array<String>();
            if (dependency.optional) {
                notes.append("optional");
            }
            if (!dependency.target.is_empty) {
                notes.append($"only for `{dependency.target}`");
            }
            out.append(notes.is_empty ? $"- {name}\n" : $"- {name} ({", ".join(notes)})\n");
        }
    }
    return out.to_string();
}

# Writes the mdBook of `manifest`'s package into `dir`: `book.toml`, and
# under `src/` the front page, `SUMMARY.md` and `pages`. A page from an
# earlier run whose file is gone goes with the rest of `src/`.
export write_book(dir: Path, manifest: Manifest, pages: Page[]): Result<void> {
    var src = dir.join("src");
    Directory.remove_all(src);
    var created = Directory.create_all(src);
    if (created.is_err()) {
        return Result<void>.Err($"cannot create {src.to_string()}: {created.error().message}");
    }
    var summary = StringBuilder();
    summary.append($"# Summary\n\n[{manifest.name}](README.md)\n\n");
    for (var page in pages) {
        if (page.file.lower() == "readme.md") {
            return Result<void>.Err(
                $"{page.title} would be the page README.md, which is the front page's; rename the file"
            );
        }
        summary.append($"- [{page.title}]({page.file})\n");
        _write_file(src.join(page.file), page.markdown)?;
    }
    _write_file(src.join("SUMMARY.md"), summary.to_string())?;
    _write_file(src.join("README.md"), package_index(manifest, pages))?;
    return _write_file(dir.join("book.toml"), $"[book]\ntitle = \"{manifest.name}\"\n");
}

_write_file(path: Path, text: String): Result<void> {
    var written = File.write_text(path, text);
    if (written.is_err()) {
        return Result<void>.Err($"cannot write {path.to_string()}: {written.error().message}");
    }
    return Result<void>.ok();
}

# Every public declaration of the package at `root` without the doc
# comment the documentation standard asks for, as clang-style errors.
export package_undocumented(root: Path): Result<String[]> {
    var errors = Array<String>();
    for (var file in package_files(root)?) {
        var path = root.join(file);
        var source = File.read_to_string(path);
        if (source.is_err()) {
            return Result<String[]>.Err($"cannot read {path.to_string()}: {source.error().message}");
        }
        var module = parse_file(file, source.value())?;
        errors.append_all(check_documented(module, source.value(), file));
    }
    return Result<String[]>.ok(errors);
}
