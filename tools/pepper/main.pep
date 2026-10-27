# pepper: the entry point to every Pepper tool, as `go` and `git` are.
#
#     pepper build main.pep -o main     # runs pep-build main.pep -o main
#     pepper fmt -w src                 # runs pep-fmt -w src
#     pepper -C src fmt -w .            # runs pep-fmt -w . in src
#     pepper help                       # lists the commands it can find
#     pepper help build                 # runs pep-build --help
#     pepper --version                  # this version; with -v, each tool's
#
# `pepper <command> arguments...` runs the program `pep-<command>`
# (`pep-<command>.exe` on Windows), looked for next to `pepper` first and
# then on the PATH, with the remaining arguments and pepper's own standard
# streams, in place of pepper (on Windows, pepper waits for it and exits
# with its exit status). Installing a `pep-<name>` program
# adds the command `<name>`.
#
# `-C <dir>` before the command changes to `dir` first, like `git -C`;
# repeated, each is relative to the one before. It and `+<version>` are
# the only options that go before a command.
#
# Installed by pep-install, pepper runs the tools of one of the toolchains
# in its Pepper home (the folder above its own): `+<version>` before the
# command picks one (`pepper +0.3 build ...`), else `PEPPER_TOOLCHAIN`,
# else `toolchain` in the nearest pep.toml, else the default; see
# tools/toolchain. The tool runs with `PEPPER_TOOLCHAIN` set to that
# version, so a `pepper` it runs uses the same toolchain. `pepper install`
# runs the home's own pep-install. Anywhere else pepper runs the tools
# beside it.
#
# A first argument that is a `.pep` file or an option is the old way of
# running the compiler (`pepper main.pep -o main`): it still runs
# `pep-build` with the whole command line, after a deprecation warning.
#
# Build it from the repository root, next to the compiler:
#
#     pep-build tools/pepper/main.pep -o target/bin/pepper

import cli;
import [Directory, File, Path] from io;
import os;
import process;
import toolchain;

# The release this entry point belongs to. `pep-doc check` keeps it equal
# to the version in VERSION.
version(): String {
    return "0.11.0";
}

main(args: String[]): int {
    ulong index = 1;
    var named = "";
    while (index < args.count and (args[index] == "-C" or args[index].starts_with("+"))) {
        if (args[index].starts_with("+")) {
            named = args[index].substr(1, args[index].length);
            index += 1;
            continue;
        }
        if (index + 1 >= args.count) {
            File.stderr().write_all("pepper: error: option '-C' requires a directory\n");
            return 2;
        }
        var directory = args[index + 1];
        # An empty directory leaves the current one as it is, as in git.
        if (!directory.is_empty) {
            var changed = process.change_working_directory(Path(directory));
            if (changed.is_err()) {
                File.stderr().write_all($"pepper: error: cannot change to '{directory}': {changed.error().message}\n");
                return 1;
            }
        }
        index += 2;
    }
    if (index >= args.count) {
        File.stderr().write_all(usage());
        return 2;
    }
    var first = args[index];
    var tools = find_toolchain(named, first == "install");
    if (tools.is_err()) {
        File.stderr().write_all($"pepper: error: {tools.error().message}\n");
        return 1;
    }
    var rest = Array<String>();
    index += 1;
    while (index < args.count) {
        rest.append(args[index]);
        index += 1;
    }
    if (first == "help" or first == "--help" or first == "-h") {
        if (first != "help" or rest.is_empty) {
            File.stdout().write_all(help(tools.value()));
            return 0;
        }
        var help_arguments = Array<String>();
        help_arguments.append("--help");
        return run_command(tools.value(), rest[0], help_arguments);
    }
    if (first == "--version") {
        return print_version(tools.value(), rest);
    }
    if (first.ends_with(".pep") or first.starts_with("-")) {
        var shown = rest.is_empty ? first : first + " ...";
        File.stderr().write_all($"pepper: warning: 'pepper {shown}' is deprecated; use 'pepper build {shown}'\n");
        var build_arguments = Array<String>();
        build_arguments.append(first);
        for (var argument in rest) {
            build_arguments.append(argument);
        }
        return run_command(tools.value(), "build", build_arguments);
    }
    return run_command(tools.value(), first, rest);
}

# Where the tools are: the directories searched for `pep-<command>`, and
# the toolchain version a tool runs with, if pepper picked one.
struct Tools {
    var directories = Array<Path>();
    var version = "";
    # Why that toolchain: `the default`.
    var reason = "";

    construct() {}
}

# The tools to run: those of the toolchain `named` (after `+`) or the
# folder's, when pepper runs from a Pepper home; else the ones beside
# pepper. `install` runs the home's pep-install, which needs no toolchain.
find_toolchain(named: String, install: bool): Result<Tools> {
    var tools = Tools();
    var home = toolchain.home_of_executable();
    if (home.is_empty()) {
        if (!named.is_empty) {
            return Result<Tools>.Err(
                $"'+{named}' picks a toolchain installed by 'pepper install'; this pepper runs the tools beside it"
            );
        }
        tools.directories = search_directories();
        return Result<Tools>.ok(tools);
    }
    if (install) {
        tools.directories.append(home.value().bin);
        return Result<Tools>.ok(tools);
    }
    var directory = Directory.current();
    if (directory.is_err()) {
        return Result<Tools>.Err($"cannot tell the current directory: {directory.error().message}");
    }
    var environment = os.environment("PEPPER_TOOLCHAIN").value_or("");
    var chosen = toolchain.choose_toolchain(home.value(), named, environment, directory.value())?;
    if (chosen.is_empty()) {
        return Result<Tools>.Err("no toolchain is installed; install the newest with 'pepper install update'");
    }
    var choice = chosen.value();
    var spec = choice.spec.to_string();
    if (choice.version.is_empty()) {
        return Result<Tools>.Err(
            $"toolchain {spec} ({choice.reason()}) is not installed; install it with 'pepper install add {spec}'"
        );
    }
    tools.version = choice.version.value().to_string();
    tools.reason = choice.reason();
    tools.directories.append(home.value().toolchain_bin(choice.version.value()));
    for (var directory in search_directories()) {
        tools.directories.append(directory);
    }
    return Result<Tools>.ok(tools);
}

# Runs `pep-<command>` with `arguments` in place of pepper, or reports why
# it cannot.
run_command(tools: Tools, command: String, arguments: Array<String>): int {
    var tool = is_command_name(command) ? find_tool(tools, command) : Optional<Path>.Empty;
    if (tool.is_empty()) {
        var message = $"pepper: error: '{command}' is not a pepper command";
        var commands = find_commands(tools);
        var best = cli.closest(command, commands);
        if (best.is_value()) {
            message = message + $"; did you mean '{best.value()}'?";
        }
        File.stderr().write_all(message + "\n\n" + command_list(commands));
        return 1;
    }
    # The tool takes over this process, so signals reach it directly and
    # its exit status is pepper's; exec returns only when it cannot start.
    var run = process.Command(tool.value().to_string()).arguments(arguments);
    if (!tools.version.is_empty) {
        run = run.environment("PEPPER_TOOLCHAIN", tools.version);
    }
    var error = run.exec();
    File.stderr().write_all($"pepper: error: {error.message}\n");
    return 1;
}

# Whether `name` can name a command: lowercase letters, digits, `-` and
# `_`, so that it never reaches outside the directories searched.
is_command_name(name: String): bool {
    if (name.is_empty) {
        return false;
    }
    ulong index = 0;
    while (index < name.size) {
        var byte = name.byte_at(index);
        var allowed = (byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9') or byte == '-' or byte == '_';
        if (!allowed) {
            return false;
        }
        index += 1;
    }
    return true;
}

# The executable for `command`: the first `pep-<command>` in the
# directories of `tools`.
find_tool(tools: Tools, command: String): Path? {
    var file_name = "pep-" + command + executable_suffix();
    for (var directory in tools.directories) {
        var candidate = directory.join(file_name);
        if (process.is_executable(candidate)) {
            return Optional<Path>.Value(candidate);
        }
    }
    return Optional<Path>.Empty;
}

# Every command a `pep-*` executable in the directories of `tools`
# provides, sorted and without repeats.
find_commands(tools: Tools): Array<String> {
    var commands = Array<String>();
    var suffix = executable_suffix();
    for (var directory in tools.directories) {
        var opened = Directory.open(directory);
        if (opened.is_err()) {
            continue;
        }
        var listed = opened.value().entries();
        if (listed.is_err()) {
            continue;
        }
        for (var entry in listed.value()) {
            var name = entry.name;
            if (!suffix.is_empty) {
                name = name.lower();
            }
            if (!name.starts_with("pep-") or !name.ends_with(suffix) or name.size <= 4 + suffix.size) {
                continue;
            }
            var command = name.substr_bytes(4, name.size - 4 - suffix.size);
            if (is_command_name(command) and !commands.contains(command) and process.is_executable(entry.path)) {
                commands.append(command);
            }
        }
    }
    commands.sort((a, b) => a.compare(b));
    return commands;
}

# The directories searched for `pep-<command>` outside a toolchain, in
# order: the one holding the running `pepper`, then each directory on the
# PATH.
search_directories(): Array<Path> {
    var directories = Array<Path>();
    var executable = process.executable_path();
    if (executable.is_ok()) {
        var parent = executable.value().parent();
        if (parent.is_value()) {
            directories.append(parent.value());
        }
    }
    var path = os.environment("PATH");
    if (path.is_value()) {
        var separator = is_windows() ? ";" : ":";
        for (var entry in path.value().split(separator)) {
            if (!entry.is_empty) {
                directories.append(Path(entry));
            }
        }
    }
    return directories;
}

is_windows(): bool {
    return os.system_os() == os.OperatingSystem.Windows;
}

executable_suffix(): String {
    return is_windows() ? ".exe" : "";
}

# `pepper --version`, and with `-v` the version each command reports.
print_version(tools: Tools, options: Array<String>): int {
    var verbose = false;
    for (var option in options) {
        if (option == "-v" or option == "--verbose") {
            verbose = true;
        } else {
            File.stderr().write_all($"pepper: error: unknown option '{option}' after '--version'\n");
            return 2;
        }
    }
    File.stdout().write_all($"pepper {version()}\n");
    if (!tools.version.is_empty) {
        File.stdout().write_all($"toolchain {tools.version} ({tools.reason})\n");
    }
    if (!verbose) {
        return 0;
    }
    for (var command in find_commands(tools)) {
        var tool = find_tool(tools, command).value();
        var reported = "(no version)";
        var ran = process.Command(tool.to_string()).argument("--version").run();
        if (ran.is_ok() and ran.value().status.success()) {
            var lines = ran.value().stdout.trim().lines();
            if (!lines.is_empty) {
                reported = lines[0];
            }
        }
        File.stdout().write_all($"  {command}: {reported}\n");
    }
    return 0;
}

usage(): String {
    return "usage: pepper [+<version>] [-C <dir>]... <command> [arguments]\n       pepper help [<command>]\n       pepper --version [-v]\n";
}

help(tools: Tools): String {
    var text = usage();
    text = text + "\nRuns the program pep-<command>, found next to pepper or on the PATH,\n";
    text = text + "with the remaining arguments.\n\n";
    text = text + "Options:\n";
    text = text + "  +<version>     run the command with that installed toolchain, such as +0.3\n";
    text = text + "  -C <dir>       run the command in <dir>; each repeat is relative to the last\n";
    text = text + "  -h, --help     show this help; 'pepper help <command>' runs 'pep-<command> --help'\n";
    text = text + "  --version      show pepper's version\n";
    text = text + "  -v, --verbose  after --version: also show each command's version\n\n";
    return text + command_list(find_commands(tools));
}

# The commands `pepper help` lists.
command_list(commands: Array<String>): String {
    if (commands.is_empty) {
        return "No commands found: no pep-* program is next to pepper or on the PATH.\n";
    }
    var text = "Commands:\n";
    for (var command in commands) {
        text = text + "  " + command + "\n";
    }
    return text;
}
