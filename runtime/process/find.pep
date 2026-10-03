## Finding programs: `find_executable` looks a program up on the `PATH`, as
## a shell does before running it, and `is_executable` tells whether a file
## can be run.

import io;
import os;

## Returns the program `name` would run as a command: the first file named
## `name` in the directories `PATH` lists, in order, that this process may
## run. A `name` that holds a path separator is not looked up: it is
## returned when it names such a file itself. On Windows, a `name` with no
## extension also matches `name.exe`.
##
## @param name the program's file name, such as `"perf"`
## @returns the program's path, or none when no directory on the `PATH`
##   holds it
## @example
##     import process;
##
##     main(): int {
##         var git = process.find_executable("git");
##         print(git.is_value() ? git.value().to_string() : "git is not installed");
##         return 0;
##     }
export find_executable(name: String): io.Path? {
    if (name.is_empty) {
        return Optional<io.Path>.Empty;
    }
    var windows = os.system_os() == os.OperatingSystem.Windows;
    var names = Array<String>();
    names.append(name);
    if (windows and io.Path(name).extension().is_empty()) {
        names.append(name + ".exe");
    }
    if (name.contains("/") or (windows and name.contains("\\"))) {
        for (var candidate in names) {
            if (is_executable(io.Path(candidate))) {
                return Optional<io.Path>.Value(io.Path(candidate));
            }
        }
        return Optional<io.Path>.Empty;
    }
    var path = os.environment("PATH");
    if (path.is_empty()) {
        return Optional<io.Path>.Empty;
    }
    for (var directory in path.value().split(windows ? ";" : ":")) {
        if (directory.is_empty) {
            continue;
        }
        for (var candidate in names) {
            var file = io.Path(directory).join(candidate);
            if (is_executable(file)) {
                return Optional<io.Path>.Value(file);
            }
        }
    }
    return Optional<io.Path>.Empty;
}

## Returns whether `path` is a file this process may run: on Linux and
## macOS, a file with an execute permission bit set; on Windows, any file.
##
## @param path the file to check
## @returns true when `path` names a file that may be run
export is_executable(path: io.Path): bool {
    var metadata = path.metadata();
    if (metadata.is_err() or !metadata.value().is_file) {
        return false;
    }
    if (os.system_os() == os.OperatingSystem.Windows) {
        return true;
    }
    return (metadata.value().permissions & 73) != 0;  # 0111
}
