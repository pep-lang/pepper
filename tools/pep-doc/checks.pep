# The checks `pep-doc check` runs besides the reference's: every public
# runtime declaration has a doc comment (AGENTS.md's documentation
# standard), and every command-line option of every tool is on the tool's
# page in the book. Each takes the options from the tool itself (`--help`,
# or a usage text the tool prints) and requires every spelling in the
# page, so adding an option without documenting it fails and names the
# page to update.
#
# | Tool | Options from | Page |
# | --- | --- | --- |
# | `pep-build` | `pep-build --help`, `TRACE_CHANNELS`, the environment variables the compiler reads | `docs/src/tools/pep-build.md` |
# | `pepper`, `pep-fmt`, `pep-profile`, `pep-test` | the tool's `--help` | `docs/src/tools/<tool>.md` |
# | `pep-package`, `pep-install` | the tool's `--help` and each command's `--help` | `docs/src/tools/<tool>.md` |
# | `pep-doc` | its own help (`HELP` in main.pep) | `docs/src/tools/pep-doc.md` |
# | `pep-lsp` | `HELP` in `tools/pep-lsp/arguments.pep`, the server's initialization options and the VS Code settings | `docs/src/tools/pep-lsp.md` |
# | `setup-llvm.sh` | its usage text, which `--help` prints | `docs/src/contributing/setup.md` |
# | `install.sh` | its `usage` text | `docs/src/tools/install.md` |
# | `install.ps1` | its `param()` block | `docs/src/tools/install.md` |
#
# It also holds each Pepper tool's `version()` to the version in the
# repository's `VERSION` file (`stale_versions`), which
# `scripts/set-version.sh` sets them all to.
#
# The tools' `--help` comes from the built tools in one folder (`--tools`,
# else `target/pepper-tests/bin`, where `scripts/pepper-tests.sh` builds the
# Pepper tools beside its `pep-build`).

import [check_documented] from compiler.doc;
import [Directory, File, Path] from io;
import os;
import process;
import "reference";
import "strings";

# The Pepper tools whose `--help` lists options, built from
# `tools/<tool>/main.pep`.
export pepper_tools(): String[] {
    return ["pepper", "pep-fmt", "pep-profile", "pep-package", "pep-install", "pep-test"];
}

# Whether `tool` has commands, each with options of its own.
_has_commands(tool: String): bool {
    return tool == "pep-package" or tool == "pep-install";
}

# The `.pep` files under `dir`, as paths from the repository root starting
# with `prefix`, leaving out tests (`test/` folders, which are not part of
# any module) and hidden folders such as `.pep/`.
_library_files(root: Path, prefix: String, out: String[]): Result<void> {
    var files = Array<String>();
    pep_files(root.join(prefix), "", files)?;
    for (var file in files) {
        out.append($"{prefix}/{file}");
    }
    return Result<void>.ok();
}

# Negative, zero or positive as path `a` sorts before, with or after `b`,
# comparing their `/`-separated parts in turn.
_compare_paths(a: String, b: String): int {
    var left = a.split("/");
    var right = b.split("/");
    ulong i = 0;
    while (i < left.count and i < right.count) {
        var order = left[i].compare(right[i]);
        if (order != 0) {
            return order;
        }
        i += 1;
    }
    if (left.count == right.count) {
        return 0;
    }
    return left.count < right.count ? -1 : 1;
}

# Every public declaration in `runtime/` and in the Pepper library under
# `tools/syntax` without the doc comment AGENTS.md asks for, rendered as
# clang-style errors.
export undocumented_declarations(root: Path): Result<String[]> {
    var files = Array<String>();
    _library_files(root, "runtime", files)?;
    if (root.join("tools").join("syntax").is_directory()) {
        _library_files(root, "tools/syntax", files)?;
    }
    files.sort((a, b) => _compare_paths(a, b));
    var errors = Array<String>();
    for (var name in files) {
        var path = root.join(name);
        var source = File.read_to_string(path);
        if (source.is_err()) {
            return Result<String[]>.Err($"cannot read {path.to_string()}: {source.error().message}");
        }
        var module = parse_file(name, source.value())?;
        errors.append_all(check_documented(module, source.value(), name));
    }
    return Result<String[]>.ok(errors);
}

# The name of the executable `name` on this system.
_executable(name: String): String {
    return os.system_os() == os.OperatingSystem.Windows ? $"{name}.exe" : name;
}

# The folder holding the built tools: `explicit`, else the one
# `scripts/pepper-tests.sh` builds them in, `target/pepper-tests/bin` (under
# `$PEPPER_TARGET_DIR` when it is set).
export tools_dir(root: Path, explicit: String?): Path {
    if (explicit.is_value()) {
        return Path(explicit.value());
    }
    var variable = os.environment("PEPPER_TARGET_DIR");
    var target = variable.is_value() ? Path(variable.value()) : root.join("target");
    return target.join("pepper-tests").join("bin");
}

# What `tool --help` (with `arguments` before `--help`) prints, from the
# build in `dir`.
_help_of(dir: Path, tool: String, arguments: String[]): Result<String> {
    var path = dir.join(_executable(tool));
    if (!path.is_file()) {
        return Result<String>.Err(
            $"cannot find {_executable(tool)} in {dir.to_string()}: build the Pepper tools with scripts/pepper-tests.sh, or name their folder with --tools"
        );
    }
    var output = process
        .Command(path.to_string())
        .arguments(arguments)
        .argument("--help")
        .stdin(process.Stream.Null)
        .stdout(process.Stream.Pipe)
        .stderr(process.Stream.Pipe)
        .run();
    if (output.is_err()) {
        return Result<String>.Err($"cannot run {path.to_string()}: {output.error().message}");
    }
    if (!output.value().status.success()) {
        var shown = arguments.is_empty ? path.to_string() : $"{path.to_string()} {" ".join(arguments)}";
        return Result<String>.Err($"{shown} --help failed ({output.value().status.to_string()})");
    }
    return Result<String>.ok(normalized(output.value().stdout));
}

# A file of the repository, by its path from the root, with LF line ends.
_repository_file(root: Path, path: String): Result<String> {
    var text = File.read_to_string(root.join(path));
    if (text.is_err()) {
        return Result<String>.Err($"cannot read {path}: {text.error().message}");
    }
    return Result<String>.ok(normalized(text.value()));
}

# Whether `b` continues an option or a name: `-O2`, `--Off`, `X_O`.
_is_part(b: byte): bool {
    return is_ascii_alphanumeric(b) or b == '-' or b == '_' or b == '.';
}

# Whether `text` mentions `word` on its own: `-O` in "`-O`" or "-O,", but
# not inside `-O2`, `--Off` or `X_O`.
export mentions(text: String, word: String): bool {
    ulong from = 0;
    while (true) {
        var found = text.find(word, from);
        if (found < 0) {
            return false;
        }
        var at = found as ulong;
        var after = at + word.size;
        bool joined_before = at > 0 and _is_part(text.byte_at(at - 1));
        bool joined_after = after < text.size and _is_part(text.byte_at(after)) and text.byte_at(after) != '.';
        if (!joined_before and !joined_after) {
            return true;
        }
        # The next match starts after this one, as matches never overlap.
        from = after;
    }
    return false;
}

# Whether `text` documents the environment variable `name`: by name, or
# for one with a part chosen at run time (`PEPPER_SYSROOT_<TRIPLE>`,
# `LLVM_SYS_<major>1_PREFIX`) by its fixed start followed by `<`.
export mentions_variable(text: String, name: String): bool {
    if (mentions(text, name)) {
        return true;
    }
    for (var i in 0..name.size) {
        if (name.byte_at(i) == '_' and text.contains(name.substr_bytes(0, i + 1) + "<")) {
            return true;
        }
    }
    return false;
}

# The lines of the section of `help` headed `heading` (`Options:`), up to
# the next line that is not indented.
_section(help: String, heading: String): String[] {
    var out = Array<String>();
    bool inside = false;
    for (var line in help.lines()) {
        if (!inside) {
            inside = line.trim_end() == heading;
            continue;
        }
        if (!line.is_empty and !line.starts_with(" ")) {
            break;
        }
        if (!line.trim().is_empty) {
            out.append(line);
        }
    }
    return out;
}

# Every option spelling the `Options:` section of `help` lists, from the
# left column of each line: `-w, --write` gives `-w` and `--write`, and
# `--site <DIR>` gives `--site`. A line indented deeper than an option's
# (`      --lto`) continues a description.
export help_options(help: String): String[] {
    var options = Array<String>();
    for (var line in _section(help, "Options:")) {
        var text = line.trim_start();
        if (!text.starts_with("-") or line.size - text.size > 6) {
            continue;
        }
        var gap = text.find("  ");
        var left = gap < 0 ? text : text.substr_bytes(0, gap as ulong);
        for (var token in _tokens(left)) {
            var spelling = _spelling(token);
            if (spelling.starts_with("-") and spelling.size > 1 and !options.contains(spelling)) {
                options.append(spelling);
            }
        }
    }
    return options;
}

# The pieces of `text` between spaces and commas, empty ones included.
_tokens(text: String): String[] {
    var out = Array<String>();
    ulong start = 0;
    for (var i in 0..text.size) {
        var b = text.byte_at(i);
        if (b == ' ' or b == ',') {
            out.append(slice(text, start, i));
            start = i + 1;
        }
    }
    out.append(slice_from(text, start));
    return out;
}

# The option a left-column token spells: `[--release]` gives `--release`,
# `--site=<DIR>` and `--site<DIR>` give `--site`.
_spelling(token: String): String {
    ulong start = 0;
    var end = token.size;
    while (start < end and (token.byte_at(start) == '[' or token.byte_at(start) == ']')) {
        start += 1;
    }
    while (end > start and (token.byte_at(end - 1) == '[' or token.byte_at(end - 1) == ']')) {
        end -= 1;
    }
    var i = start;
    while (i < end and token.byte_at(i) != '=' and token.byte_at(i) != '<' and token.byte_at(i) != '[') {
        i += 1;
    }
    return slice(token, start, i);
}

# Each `--option value` the `Options:` section of clap's `help` lists as
# `[possible values: a, b]`.
export help_values(help: String): String[] {
    var values = Array<String>();
    var marker = "[possible values: ";
    for (var line in _section(help, "Options:")) {
        var at = line.find(marker);
        if (at < 0) {
            continue;
        }
        var spellings = help_options($"Options:\n{line}");
        if (spellings.is_empty) {
            continue;
        }
        var spelling = spellings.last();
        var list = slice_from(line, at as ulong + marker.size);
        var close = list.find("]");
        if (close >= 0) {
            list = list.substr_bytes(0, close as ulong);
        }
        for (var value in list.split(", ")) {
            values.append($"{spelling} {value.trim()}");
        }
    }
    return values;
}

# The command names the `Commands:` section of `help` lists.
export help_commands(help: String): String[] {
    var commands = Array<String>();
    for (var line in _section(help, "Commands:")) {
        var parts = words(line);
        if (!parts.is_empty) {
            commands.append(parts[0]);
        }
    }
    return commands;
}

# Whether `b` can be part of an environment variable's name.
_is_name_byte(b: byte): bool {
    return (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '_';
}

# The name of an environment variable starting at `at` in `text`.
_name_at(text: String, at: ulong): String {
    var end = at;
    while (end < text.size and _is_name_byte(text.byte_at(end))) {
        end += 1;
    }
    return slice(text, at, end);
}

# `names` sorted, each once.
_sorted_once(names: String[]): String[] {
    names.sort((a, b) => a.compare(b));
    var out = Array<String>();
    for (var name in names) {
        if (out.is_empty or out.last() != name) {
            out.append(name);
        }
    }
    return out;
}

# The environment variables (`PEPPER_*`) that `text` names.
export variables_named(text: String): String[] {
    var names = Array<String>();
    ulong from = 0;
    while (true) {
        var found = text.find("PEPPER_", from);
        if (found < 0) {
            break;
        }
        var at = found as ulong;
        from = at + 1;
        if (at > 0 and (is_ascii_alphanumeric(text.byte_at(at - 1)) or text.byte_at(at - 1) == '_')) {
            continue;
        }
        names.append(_name_at(text, at));
    }
    return _sorted_once(names);
}

# The string literals in the Pepper sources under `dir` that name a
# `PEPPER_*` or other environment variable the tools read.
_variables_read(dir: Path, names: String[]): Result<void> {
    var listing = Directory.open(dir);
    if (listing.is_err()) {
        return Result<void>.Err($"cannot read {dir.to_string()}: {listing.error().message}");
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return Result<void>.Err($"cannot read {dir.to_string()}: {entries.error().message}");
    }
    var sorted = entries.value();
    sorted.sort((a, b) => a.name.compare(b.name));
    for (var entry in sorted) {
        if (entry.is_directory) {
            # `.pep` holds fetched packages, not the tool's own sources.
            if (!entry.name.starts_with(".")) {
                _variables_read(entry.path, names)?;
            }
            continue;
        }
        if (!entry.name.ends_with(".pep")) {
            continue;
        }
        var text = File.read_to_string(entry.path);
        if (text.is_err()) {
            return Result<void>.Err($"cannot read {entry.path.to_string()}: {text.error().message}");
        }
        var source = text.value();
        for (var i in 0..source.size) {
            if (source.byte_at(i) != '"') {
                continue;
            }
            var name = _name_at(source, i + 1);
            bool known = name.starts_with("PEPPER_") or name.starts_with("LLVM_SYS_") or name == "NO_COLOR";
            # A name the source completes (`$"PEPPER_PACKAGE_{host}_URL"`)
            # is documented by its spellings.
            if (known and !name.ends_with("_") and !names.contains(name)) {
                names.append(name);
            }
        }
    }
    return Result<void>.ok();
}

# The trace channels `-T` takes: `TRACE_CHANNELS` in the compiler's
# `main.pep`.
_trace_channels(root: Path): Result<String[]> {
    var path = "tools/compiler/main.pep";
    var source = _repository_file(root, path)?;
    var marker = "const TRACE_CHANNELS = \"";
    var start = source.find(marker);
    if (start < 0) {
        return Result<String[]>.Err($"no TRACE_CHANNELS in {path}");
    }
    var list = slice_from(source, start as ulong + marker.size);
    var close = list.find("\"");
    if (close < 0) {
        return Result<String[]>.Err($"TRACE_CHANNELS in {path} is not a string");
    }
    var channels = Array<String>();
    for (var channel in list.substr_bytes(0, close as ulong).split(" ")) {
        if (!channel.is_empty) {
            channels.append(channel);
        }
    }
    return Result<String[]>.ok(channels);
}

# How a check finds a word in a page.
enum _Match {
    # The word on its own (`mentions`).
    Word,
    # An environment variable (`mentions_variable`).
    Variable,
    # An option value, as `--lto full` or `--lto=full`.
    Value,
}

_documents(text: String, word: String, how: _Match): bool {
    match (how) {
        Word => {
            return mentions(text, word);
        }
        Variable => {
            return mentions_variable(text, word);
        }
        Value => {
            return mentions(text, word) or mentions(text, replace_first(word, " ", "="));
        }
    }
    return false;
}

# Adds to `problems` each of `words` that page `page_path` of `tool` does
# not mention, as `what`.
_undocumented(
    root: Path, tool: String, page_path: String, what: String, words: String[], how: _Match, problems: String[]
): Result<void> {
    if (words.is_empty) {
        return Result<void>.Err($"{tool}: found no {what}s to check against {page_path}");
    }
    var text = _repository_file(root, page_path)?;
    for (var word in words) {
        if (!_documents(text, word, how)) {
            problems.append($"{tool}: {what} '{word}' is not documented in {page_path}; add it there");
        }
    }
    return Result<void>.ok();
}

# Every option, command, setting and environment variable of the tools
# that its page leaves out, one line each; the tools' `--help` comes from
# the builds in `tools`, and `pep-doc`'s from `pep_doc_help`.
export undocumented_tool_options(root: Path, tools: Path, pep_doc_help: String): Result<String[]> {
    var problems = Array<String>();

    # pep-build (pepc, `tools/compiler`): its options and their values,
    # trace channels, and every environment variable it reads.
    var pep_build = "docs/src/tools/pep-build.md";
    var help = _help_of(tools, "pep-build", Array<String>())?;
    _undocumented(root, "pep-build", pep_build, "option", help_options(help), _Match.Word, problems)?;
    _undocumented(root, "pep-build", pep_build, "option value", help_values(help), _Match.Value, problems)?;
    var channels = Array<String>();
    for (var channel in _trace_channels(root)?) {
        channels.append($"-T {channel}");
    }
    _undocumented(root, "pep-build", pep_build, "trace channel", channels, _Match.Word, problems)?;
    var variables = Array<String>();
    _variables_read(root.join("tools").join("compiler"), variables)?;
    _undocumented(root, "pep-build", pep_build, "environment variable", variables, _Match.Variable, problems)?;

    # The Pepper tools, from their --help.
    for (var tool in pepper_tools()) {
        var page = $"docs/src/tools/{tool}.md";
        var tool_help = _help_of(tools, tool, Array<String>())?;
        _undocumented(root, tool, page, "option", help_options(tool_help), _Match.Word, problems)?;
        if (!_has_commands(tool)) {
            continue;
        }
        var commands = help_commands(tool_help);
        _undocumented(root, tool, page, "command", commands, _Match.Word, problems)?;
        for (var command in commands) {
            var options = help_options(_help_of(tools, tool, [command])?);
            _undocumented(root, tool, page, $"'{command}' option", options, _Match.Word, problems)?;
        }
    }

    # pep-doc, from the help it prints.
    var pep_doc = "docs/src/tools/pep-doc.md";
    var doc_commands = Array<String>();
    for (var command in help_commands(pep_doc_help)) {
        doc_commands.append($"pep-doc {command}");
    }
    _undocumented(root, "pep-doc", pep_doc, "option", help_options(pep_doc_help), _Match.Word, problems)?;
    _undocumented(root, "pep-doc", pep_doc, "command", doc_commands, _Match.Word, problems)?;

    _lsp(root, problems)?;

    # setup-llvm.sh, from the usage at its top, which `--help` prints.
    var setup = "docs/src/contributing/setup.md";
    var script = _repository_file(root, "scripts/setup-llvm.sh")?;
    var usage = "";
    for (var line in script.lines()) {
        if (line.starts_with("set -euo pipefail")) {
            break;
        }
        if (line.starts_with("# ")) {
            usage += line.substr_bytes(2, line.size - 2) + "\n";
        } else {
            usage += "\n";
        }
    }
    _undocumented(root, "setup-llvm.sh", setup, "option", help_options(usage), _Match.Word, problems)?;
    _undocumented(root, "setup-llvm.sh", setup, "environment variable", variables_named(usage), _Match.Word, problems)?;

    _install_scripts(root, problems)?;
    return Result<String[]>.ok(problems);
}

# pep-lsp: its options (`HELP` in tools/pep-lsp/arguments.pep), the
# initialization options the server reads (`json_flag(params.
# initialization_options, ["inlayHints", "parameterNames"], ...)` and
# `options.value().contains("buildOptions")` in tools/pep-lsp/server.pep,
# spelled with dots), and the VS Code extension's settings and commands
# (`pepper.lspPath`).
_lsp(root: Path, problems: String[]): Result<void> {
    var page = "docs/src/tools/pep-lsp.md";
    var main = _repository_file(root, "tools/pep-lsp/arguments.pep")?;
    var help_start = "const HELP = \"";
    var help_at = main.find(help_start);
    if (help_at < 0) {
        return Result<void>.Err("tools/pep-lsp/arguments.pep declares no HELP");
    }
    var help_from = help_at as ulong + help_start.size;
    var help = slice(main, help_from, find_byte(main, '"', help_from, main.size));
    var server = _repository_file(root, "tools/pep-lsp/server.pep")?;
    var initialization = Array<String>();
    var flag = "json_flag(params.initialization_options, [";
    ulong from = 0;
    while (true) {
        var found = server.find(flag, from);
        if (found < 0) {
            break;
        }
        var start = found as ulong + flag.size;
        var end = find_byte(server, ']', start, server.size);
        from = end;
        # The quoted keys of the path, joined with dots.
        var name = String();
        var at = start;
        while (at < end) {
            var open = find_byte(server, '"', at, end);
            if (open == end) {
                break;
            }
            var close = find_byte(server, '"', open + 1, end);
            if (!name.is_empty) {
                name.append(".");
            }
            name.append(slice(server, open + 1, close));
            at = close + 1;
        }
        initialization.append(name);
    }
    var contains = "options.value().contains(\"";
    from = 0;
    while (true) {
        var found = server.find(contains, from);
        if (found < 0) {
            break;
        }
        var start = found as ulong + contains.size;
        from = start;
        initialization.append(slice(server, start, find_byte(server, '"', start, server.size)));
    }
    var package = _repository_file(root, "tools/vscode-pepper/package.json")?;
    var settings = Array<String>();
    from = 0;
    while (true) {
        var found = package.find("\"pepper.", from);
        if (found < 0) {
            break;
        }
        var start = found as ulong + 1;
        from = start;
        settings.append(slice(package, start, find_byte(package, '"', start, package.size)));
    }
    _undocumented(root, "pep-lsp", page, "option", help_options(help), _Match.Word, problems)?;
    _undocumented(root, "pep-lsp", page, "initialization option", _sorted_once(initialization), _Match.Word, problems)?;
    _undocumented(root, "pep-lsp", page, "VS Code setting or command", _sorted_once(settings), _Match.Word, problems)?;
    return Result<void>.ok();
}

# The name `line` of install.ps1's `param()` block declares
# (`[string]$Version = ...` declares `Version`); empty for any other line.
_parameter_name(line: String): String {
    for (var prefix in ["[string]$", "[switch]$"]) {
        if (!line.starts_with(prefix)) {
            continue;
        }
        var rest = slice_from(line, prefix.size);
        ulong end = 0;
        while (end < rest.size and rest.byte_at(end) != ' ' and rest.byte_at(end) != ',') {
            end += 1;
        }
        return slice(rest, 0, end);
    }
    return "";
}

# The install scripts: install.sh's usage text and the variables it reads,
# and install.ps1's `[string]$Version = ...` and `[switch]$Yes`
# parameters.
_install_scripts(root: Path, problems: String[]): Result<void> {
    var page = "docs/src/tools/install.md";
    var script = _repository_file(root, "scripts/install.sh")?;
    var usage_start = script.find("<<'EOF'\n");
    if (usage_start < 0) {
        return Result<void>.Err("scripts/install.sh has no usage text");
    }
    var usage = slice_from(script, usage_start as ulong + 8);
    var usage_end = usage.find("\nEOF");
    if (usage_end >= 0) {
        usage = usage.substr_bytes(0, usage_end as ulong);
    }
    _undocumented(root, "install.sh", page, "option", help_options(usage), _Match.Word, problems)?;
    _undocumented(root, "install.sh", page, "environment variable", variables_named(script), _Match.Word, problems)?;
    var parameters = Array<String>();
    bool inside = false;
    var parameters_script = _repository_file(root, "scripts/install.ps1")?;
    for (var line in parameters_script.lines()) {
        if (!inside and !line.starts_with("param(")) {
            continue;
        }
        inside = true;
        if (line == ")") {
            break;
        }
        var parameter = _parameter_name(line.trim());
        if (!parameter.is_empty) {
            parameters.append("-" + parameter);
        }
    }
    _undocumented(root, "install.ps1", page, "parameter", parameters, _Match.Word, problems)?;
    return Result<void>.ok();
}

# The version `version()` returns in the `main.pep` source of a tool: the
# string literal of the `return` after `version(): String {`. None when
# the source has no such function.
export tool_version(source: String): String? {
    var start = source.find("\nversion(): String {");
    if (start < 0) {
        return Optional<String>.Empty;
    }
    var marker = "return \"";
    var at = source.find(marker, start as ulong);
    if (at < 0) {
        return Optional<String>.Empty;
    }
    var from = at as ulong + marker.size;
    var end = find_byte(source, '"', from, source.size);
    if (end == source.size) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(slice(source, from, end));
}

# Each Pepper tool (`tools/<tool>/main.pep`) whose `version()` is not the
# version in `VERSION`, one line each.
export stale_versions(root: Path): Result<String[]> {
    var held = _repository_file(root, "VERSION")?.trim();
    if (held.is_empty) {
        return Result<String[]>.Err("VERSION holds no version");
    }
    var tools = root.join("tools");
    var listing = Directory.open(tools);
    if (listing.is_err()) {
        return Result<String[]>.Err($"cannot read tools/: {listing.error().message}");
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return Result<String[]>.Err($"cannot read tools/: {entries.error().message}");
    }
    var sorted = entries.value();
    sorted.sort((a, b) => a.name.compare(b.name));
    var problems = Array<String>();
    ulong checked = 0;
    for (var entry in sorted) {
        var path = $"tools/{entry.name}/main.pep";
        if (!entry.is_directory or !root.join(path).is_file()) {
            continue;
        }
        var version = tool_version(_repository_file(root, path)?);
        if (version.is_empty()) {
            continue;
        }
        checked += 1;
        if (version.value() != held) {
            problems.append(
                $"{path}: version() returns '{version.value()}', but VERSION holds '{held}'; run scripts/set-version.sh"
            );
        }
    }
    if (checked == 0) {
        return Result<String[]>.Err("found no tools/<tool>/main.pep with a version() to check against VERSION");
    }
    return Result<String[]>.ok(problems);
}
