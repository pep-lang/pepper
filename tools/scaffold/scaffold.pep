# What `pep-new` and `pep-init` share: their options, and writing a new
# project's files into a folder. A program gets `pep.toml`, `main.pep`
# (with a `[Test]`), `.gitignore` and `README.md`; a package (`--lib`)
# gets pep-lang/pepper-package-template's files (`template.pep`), named
# for it. `--license` adds `LICENSE`. Nothing is written when any of the
# files is there already.

import cli;
import [Directory, File, Path] from io;
import syntax;
import "template";

# The options both tools take.
export struct Options {
    [cli.Option(help = "make a package: a root module.pep, its tests, and CI and release workflows")]
    var lib: bool;
    [cli.Option(help = "write a LICENSE and name it in pep.toml: MIT or Apache-2.0", value_name = "SPDX")]
    var license: String?;
    [cli.Option(help = "the package's name, instead of the folder's")]
    var name: String?;
}

# Writes a new project into `folder` (made when missing), named
# `options.name` or else after the folder, and says what it made; reports
# an error as `tool`. Returns the exit status.
export create(tool: String, folder: Path, options: Options): int {
    var name = options.name.is_value() ? options.name.value() : _folder_name(folder);
    if (!syntax.is_identifier(name)) {
        var reserved = syntax.is_reserved_word(name, syntax.Token(syntax.TokenKind.Identifier, 0, name.size));
        var message = reserved ?
            $"package name '{name}' is a reserved word, which 'import' cannot name" :
            $"package name '{name}' is not an identifier: use letters, digits and '_', not starting with a digit";
        var fixed = syntax.to_identifier(name);
        if (!fixed.is_empty) {
            message = message + $"; try '--name {fixed}'";
        }
        return _fail(tool, message);
    }
    var license = options.license.value_or("");
    if (!license.is_empty and license != "MIT" and license != "Apache-2.0") {
        return _fail(tool, $"no license text for '{license}': --license takes MIT or Apache-2.0");
    }

    var files = options.lib ? _package_files(name, license) : _program_files(name, license);
    if (license == "MIT") {
        files["LICENSE"] = _mit_license(name);
    } else if (license == "Apache-2.0") {
        files["LICENSE"] = apache_license();
    }
    var existing = Array<String>();
    for (var (path, _) in files) {
        if (folder.join(path).exists()) {
            existing.append(path);
        }
    }
    if (!existing.is_empty) {
        var list = "";
        for (var path in existing) {
            list = list + $"\n  {folder.join(path)}";
        }
        return _fail(tool, $"nothing written: these files are there already{list}");
    }
    var done = Array<Path>();
    for (var (path, text) in files) {
        var file = folder.join(path);
        var made = Directory.create_all(file.parent().value());
        var written = made.is_err() ? made : File.write_text(file, text);
        if (written.is_err()) {
            # Take back what this run wrote (none of it was there before), so
            # a retry is not refused over half a project.
            for (var earlier in done) {
                File.remove(earlier);
            }
            return _fail(tool, $"cannot write '{file}': {written.error().message}");
        }
        done.append(file);
        if (path.ends_with(".sh")) {
            file.set_executable(true);
        }
    }
    print($"Created {options.lib ? "package" : "program"} '{name}' in {folder}");
    return 0;
}

# The name of `folder` itself, even when it is written `.` or `a/..`.
_folder_name(folder: Path): String {
    var full = folder;
    if (!full.is_absolute()) {
        var here = Directory.current();
        if (here.is_ok()) {
            full = here.value().join(folder);
        }
    }
    return full.normalize().file_name().value_or("");
}

# The template's files, for the package `name` under `license` (none when
# empty).
_package_files(name: String, license: String): OrderedMap<String, String> {
    var files = OrderedMap<String, String>();
    for (var (path, text) in package_files()) {
        var named = text.replace("mypkg", name);
        if (path == "pep.toml") {
            named = named.replace("license = \"Apache-2.0\"\n", _license_key(license));
        } else if (path == "README.md") {
            named = named.replace(_license_section("Apache-2.0"), _license_section(license));
        }
        files[path] = named;
    }
    return files;
}

# A program's files, for the program `name` under `license`.
_program_files(name: String, license: String): OrderedMap<String, String> {
    var files = OrderedMap<String, String>();
    files["pep.toml"] = $"[package]\nname = \"{name}\"\nversion = \"0.1.0\"\n{_license_key(license)}";
    files["main.pep"] = "# Prints a greeting. `pepper build` builds it and `pepper test` runs its\n"
        + "# tests.\n\n"
        + "# The greeting for `who`.\n"
        + "greeting(who: String): String {\n    return $\"Hello, {who}!\";\n}\n\n"
        + "main(): int {\n    print(greeting(\"world\"));\n    return 0;\n}\n\n"
        + "# `pepper test` runs each `[Test]` function; a plain build leaves them out.\n"
        + "[Test]\ngreets_by_name() {\n    expect_equal(greeting(\"Ada\"), \"Hello, Ada!\");\n}\n";
    files[".gitignore"] = $"/.pep/\n/{name}\n/{name}.exe\n/{name}.pdb\n";
    files["README.md"] = $"# {name}\n\nA [Pepper](https://github.com/pep-lang/pepper) program.\n\n```sh\n"
        + $"pepper build   # builds ./{name}\npepper run     # builds it and runs it\n"
        + "pepper test    # runs the [Test] functions\n```\n"
        + _license_section(license);
    return files;
}

# The `license` line of `pep.toml`, or nothing for no license.
_license_key(license: String): String {
    return license.is_empty ? "" : $"license = \"{license}\"\n";
}

# The README's closing section naming `license`, or nothing for none.
_license_section(license: String): String {
    return license.is_empty ? "" : $"\n## License\n\n{license}; see [LICENSE](LICENSE).\n";
}

# The MIT License, for the authors of `name`.
_mit_license(name: String): String {
    return $"MIT License\n\nCopyright (c) The {name} authors\n\n"
        + "Permission is hereby granted, free of charge, to any person obtaining a copy\n"
        + "of this software and associated documentation files (the \"Software\"), to deal\n"
        + "in the Software without restriction, including without limitation the rights\n"
        + "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n"
        + "copies of the Software, and to permit persons to whom the Software is\n"
        + "furnished to do so, subject to the following conditions:\n\n"
        + "The above copyright notice and this permission notice shall be included in all\n"
        + "copies or substantial portions of the Software.\n\n"
        + "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n"
        + "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n"
        + "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n"
        + "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n"
        + "LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n"
        + "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\n"
        + "SOFTWARE.\n";
}

_fail(tool: String, message: String): int {
    File.stderr().write_all($"{tool}: error: {message}\n");
    return 1;
}
