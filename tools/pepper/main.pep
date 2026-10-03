# pepper: the entry point to every Pepper tool, as `go` and `git` are.
#
#     pepper build main.pep -o main     # runs pep-build main.pep -o main
#     pepper fmt -w src                 # runs pep-fmt -w src
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
# A first argument that is a `.pep` file or an option is the old way of
# running the compiler (`pepper main.pep -o main`): it still runs
# `pep-build` with the whole command line, after a deprecation warning.
#
# Build it from the repository root, next to the compiler:
#
#     target/release/pep-build tools/pepper/main.pep -o target/release/pepper

import cli;
import [Directory, File, Path] from io;
import os;
import process;

# The release this entry point belongs to. A test keeps it equal to the
# workspace version in Cargo.toml.
version(): String {
    return "0.3.0";
}

main(args: String[]): int {
    if (args.count < 2) {
        File.stderr().write_all(usage());
        return 2;
    }
    var first = args[1];
    var rest = Array<String>();
    ulong index = 2;
    while (index < args.count) {
        rest.append(args[index]);
        index += 1;
    }
    if (first == "help" or first == "--help" or first == "-h") {
        if (first != "help" or rest.is_empty) {
            File.stdout().write_all(help());
            return 0;
        }
        var help_arguments = Array<String>();
        help_arguments.append("--help");
        return run_command(rest[0], help_arguments);
    }
    if (first == "--version") {
        return print_version(rest);
    }
    if (first.ends_with(".pep") or first.starts_with("-")) {
        var shown = rest.is_empty ? first : first + " ...";
        File.stderr().write_all($"pepper: warning: 'pepper {shown}' is deprecated; use 'pepper build {shown}'\n");
        var build_arguments = Array<String>();
        build_arguments.append(first);
        for (var argument in rest) {
            build_arguments.append(argument);
        }
        return run_command("build", build_arguments);
    }
    return run_command(first, rest);
}

# Runs `pep-<command>` with `arguments` in place of pepper, or reports why
# it cannot.
run_command(command: String, arguments: Array<String>): int {
    var tool = is_command_name(command) ? find_tool(command) : Optional<Path>.Empty;
    if (tool.is_empty()) {
        var message = $"pepper: error: '{command}' is not a pepper command";
        var commands = find_commands();
        var best = cli.closest(command, commands);
        if (best.is_value()) {
            message = message + $"; did you mean '{best.value()}'?";
        }
        File.stderr().write_all(message + "\n\n" + command_list(commands));
        return 1;
    }
    # The tool takes over this process, so signals reach it directly and
    # its exit status is pepper's; exec returns only when it cannot start.
    var error = process.Command(tool.value().to_string()).arguments(arguments).exec();
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
# directories `search_directories` lists.
find_tool(command: String): Path? {
    var file_name = "pep-" + command + executable_suffix();
    for (var directory in search_directories()) {
        var candidate = directory.join(file_name);
        if (is_executable(candidate)) {
            return Optional<Path>.Value(candidate);
        }
    }
    return Optional<Path>.Empty;
}

# Every command a `pep-*` executable in the searched directories provides,
# sorted and without repeats.
find_commands(): Array<String> {
    var commands = Array<String>();
    var suffix = executable_suffix();
    for (var directory in search_directories()) {
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
            if (is_command_name(command) and !commands.contains(command) and is_executable(entry.path)) {
                commands.append(command);
            }
        }
    }
    commands.sort((a, b) => a.compare(b));
    return commands;
}

# The directories searched for `pep-<command>`, in order: the one holding
# the running `pepper`, then each directory on the PATH.
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

# Whether `path` is a file this process may run: on POSIX, one with an
# execute permission bit set.
is_executable(path: Path): bool {
    var metadata = path.metadata();
    if (metadata.is_err() or !metadata.value().is_file) {
        return false;
    }
    return is_windows() or (metadata.value().permissions & 73) != 0;  # 0111
}

is_windows(): bool {
    return os.system_os() == os.OperatingSystem.Windows;
}

executable_suffix(): String {
    return is_windows() ? ".exe" : "";
}

# `pepper --version`, and with `-v` the version each command reports.
print_version(options: Array<String>): int {
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
    if (!verbose) {
        return 0;
    }
    for (var command in find_commands()) {
        var tool = find_tool(command).value();
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
    return "usage: pepper <command> [arguments]\n       pepper help [<command>]\n       pepper --version [-v]\n";
}

help(): String {
    var text = usage();
    text = text + "\nRuns the program pep-<command>, found next to pepper or on the PATH,\n";
    text = text + "with the remaining arguments.\n\n";
    text = text + "Options:\n";
    text = text + "  -h, --help     show this help; 'pepper help <command>' runs 'pep-<command> --help'\n";
    text = text + "  --version      show pepper's version\n";
    text = text + "  -v, --verbose  after --version: also show each command's version\n\n";
    return text + command_list(find_commands());
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
