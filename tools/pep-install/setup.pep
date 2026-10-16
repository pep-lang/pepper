# `pepper install setup` and `pepper install uninstall`: setting a machine
# up for Pepper, as the install scripts do through them, and taking it
# down again.
#
# setup installs a toolchain and makes it the default, puts the home's
# `pepper` and `pep-install` in place, adds the home's `bin` to the PATH,
# offers to install what linking a program needs, and builds and runs a
# small program to show the install works. The PATH is set in the shell
# startup files (`~/.profile`, `~/.bashrc`, `~/.bash_profile`, `~/.zshrc`,
# fish's `conf.d/pepper.fish`), each change marked by a comment line, or on
# Windows in the user's PATH. uninstall removes the home and those changes.

import [Directory, File, Path] from io;
import os;
import process;
import toolchain;
import "commands";
import "releases";

# The comment line above each PATH change in a shell startup file.
export const PATH_MARKER = "# Added by the Pepper installer";

# What `pepper install setup` was asked to do.
export struct SetupOptions {
    # The toolchain to install, when there is no `archive`.
    var spec = toolchain.VersionSpec();
    # A downloaded release archive to install instead, with its `.sha256`
    # beside it.
    var archive = Optional<Path>.Empty;
    # Install missing prerequisites without asking.
    var assume_yes = false;
    var modify_path = true;
    var prerequisites = true;

    construct() {}
}

# Sets this machine up for Pepper as `options` say, printing what it does.
export setup(home: toolchain.Home, options: SetupOptions): Result<void> {
    var version = _install(home, options)?;
    # A toolchain from before side-by-side toolchains has no entry point.
    if (!home.toolchain_bin(version).join("pepper" + toolchain.executable_suffix()).is_file()) {
        return Result<void>.Err(
            $"Pepper {version.to_string()} is older than side-by-side toolchains and cannot be set up; install a newer one"
        );
    }
    home.set_default(version)?;
    update_entry_points(home, version)?;
    _say($"installed Pepper {version.to_string()} in {home.root.to_string()} and made it the default");
    _set_path(home, options.modify_path)?;
    if (options.prerequisites) {
        _check_prerequisites(options.assume_yes);
    }
    return _check_install(home, options);
}

_install(home: toolchain.Home, options: SetupOptions): Result<toolchain.Version> {
    if (options.archive.is_value()) {
        _say($"installing {options.archive.value().to_string()} into {home.root.to_string()}");
        return install_archive(home, options.archive.value());
    }
    var target = toolchain.target_name();
    if (target.is_empty()) {
        return Result<toolchain.Version>.Err("there are no Pepper releases for this machine");
    }
    var releases = fetch_releases(releases_url(), target.value())?;
    for (var release in releases) {
        if (!options.spec.matches(release.version)) {
            continue;
        }
        _say($"installing Pepper {release.version.to_string()} ({target.value()}) into {home.root.to_string()}");
        install_release(home, release)?;
        return Result<toolchain.Version>.ok(release.version);
    }
    return Result<toolchain.Version>.Err(
        $"no release is {options.spec.to_string()} with an archive for this machine; 'pepper install list --available' lists them"
    );
}

# Removes the Pepper home and the PATH changes setup made for it.
export uninstall(home: toolchain.Home): Result<String> {
    var text = "";
    if (!home.root.exists()) {
        text = $"nothing is installed in {home.root.to_string()}\n";
    } else {
        var flat = home.bin.join("pep-build" + toolchain.executable_suffix());
        if (!home.toolchains.is_directory() and !flat.is_file()) {
            return Result<String>.Err(
                $"{home.root.to_string()} does not look like a Pepper home (no toolchains or bin/pep-build); remove it yourself"
            );
        }
        var removed = Directory.remove_all(home.root);
        if (removed.is_err()) {
            return Result<String>.Err($"cannot remove {home.root.to_string()}: {removed.error().message}");
        }
        text = $"removed {home.root.to_string()}\n";
    }
    if (toolchain.is_windows()) {
        return Result<String>.ok(text + _remove_from_windows_path(home.bin)?);
    }
    for (var file in startup_files(_user_home(), _shell())) {
        if (remove_path_lines(file, home.bin)?) {
            text = text + $"removed the PATH line from {file.to_string()}\n";
        }
    }
    var fish = fish_file(_config_home());
    var fish_text = File.read_to_string(fish);
    if (fish_text.is_ok() and fish_text.value().contains($"{PATH_MARKER}\nfish_add_path \"{home.bin.to_string()}\"")) {
        File.remove(fish);
        text = text + $"removed {fish.to_string()}\n";
    }
    return Result<String>.ok(text);
}

# ── The PATH ─────────────────────────────────────────────────────────────────

_set_path(home: toolchain.Home, modify: bool): Result<void> {
    var bin = home.bin.to_string();
    var current = os.environment("PATH").value_or("");
    if (path_lists(current, bin, toolchain.is_windows())) {
        return Result<void>.ok();
    }
    if (!modify) {
        _say($"add {bin} to your PATH to run pepper");
        return Result<void>.ok();
    }
    if (toolchain.is_windows()) {
        return _add_to_windows_path(home.bin);
    }
    for (var file in startup_files(_user_home(), _shell())) {
        if (add_path_line(file, home.bin)?) {
            _say($"added {bin} to the PATH in {file.to_string()}");
        }
    }
    if (process.find_executable("fish").is_value()) {
        var fish = fish_file(_config_home());
        var created = Directory.create_all(fish.parent().value());
        if (created.is_err()) {
            return Result<void>.Err($"cannot create {fish.parent().value().to_string()}: {created.error().message}");
        }
        var written = File.write_text(fish, $"{PATH_MARKER}\nfish_add_path \"{bin}\"\n");
        if (written.is_err()) {
            return Result<void>.Err($"cannot write {fish.to_string()}: {written.error().message}");
        }
        _say($"added {bin} to the PATH in {fish.to_string()}");
    }
    _say($"open a new terminal, or run: export PATH=\"{bin}:$PATH\"");
    return Result<void>.ok();
}

# Whether the PATH `value` lists the folder `bin`; on Windows, ignoring
# case and a trailing `\`.
export path_lists(value: String, bin: String, windows: bool): bool {
    var wanted = _path_entry(bin, windows);
    for (var entry in value.split(windows ? ";" : ":")) {
        if (_path_entry(entry, windows) == wanted) {
            return true;
        }
    }
    return false;
}

_path_entry(entry: String, windows: bool): String {
    if (!windows) {
        return entry;
    }
    var lowered = entry.lower();
    return lowered.ends_with("\\") ? lowered.substr_bytes(0, lowered.size - 1) : lowered;
}

# The shell startup files that set the PATH for the user whose home folder
# is `user_home`: `.profile`, then `.bashrc` and `.bash_profile` when they
# exist, and `.zshrc` when it exists or `shell` is zsh.
export startup_files(user_home: Path, shell: String): Array<Path> {
    var files = [user_home.join(".profile")];
    for (var name in [".bashrc", ".bash_profile"]) {
        if (user_home.join(name).is_file()) {
            files.append(user_home.join(name));
        }
    }
    var zshrc = user_home.join(".zshrc");
    if (zshrc.is_file() or shell == "zsh") {
        files.append(zshrc);
    }
    return files;
}

# fish's file for Pepper in `config_home` (`$XDG_CONFIG_HOME`, else
# `~/.config`).
export fish_file(config_home: Path): Path {
    return config_home.join("fish").join("conf.d").join("pepper.fish");
}

# Adds the marker and a line putting `bin` on the PATH to the startup file
# `file`, unless it has them. Returns whether it added them.
export add_path_line(file: Path, bin: Path): Result<bool> {
    var lines = $"{PATH_MARKER}\nexport PATH=\"{bin.to_string()}:$PATH\"\n";
    var read = File.read_to_string(file);
    var text = read.is_ok() ? read.value() : "";
    if (text.contains(lines)) {
        return Result<bool>.ok(false);
    }
    var written = File.write_text(file, text + "\n" + lines);
    if (written.is_err()) {
        return Result<bool>.Err($"cannot write {file.to_string()}: {written.error().message}");
    }
    return Result<bool>.ok(true);
}

# Removes from the startup file `file` each marker line followed by a line
# putting `bin` on the PATH, and those lines. Returns whether it held any.
export remove_path_lines(file: Path, bin: Path): Result<bool> {
    if (!_has_marker(file)) {
        return Result<bool>.ok(false);
    }
    var lines = File.read_to_string(file).value().split("\n");
    var added = $"export PATH=\"{bin.to_string()}:$PATH\"";
    var kept = Array<String>();
    var removed = false;
    ulong index = 0;
    while (index < lines.count) {
        var line = lines[index];
        index += 1;
        if (line != PATH_MARKER or index >= lines.count or lines[index] != added) {
            kept.append(line);
            continue;
        }
        index += 1;
        removed = true;
        # The blank line add_path_line put before it.
        if (!kept.is_empty and kept[kept.count - 1].is_empty) {
            kept.remove_at(kept.count - 1);
        }
    }
    if (!removed) {
        return Result<bool>.ok(false);
    }
    var written = File.write_text(file, "\n".join(kept));
    if (written.is_err()) {
        return Result<bool>.Err($"cannot write {file.to_string()}: {written.error().message}");
    }
    return Result<bool>.ok(true);
}

_has_marker(file: Path): bool {
    var text = File.read_to_string(file);
    return text.is_ok() and text.value().contains(PATH_MARKER);
}

_user_home(): Path {
    return os.home_directory().value_or(Path("."));
}

_config_home(): Path {
    var variable = os.environment("XDG_CONFIG_HOME");
    if (variable.is_value() and !variable.value().is_empty) {
        return Path(variable.value());
    }
    return _user_home().join(".config");
}

# The name of the user's shell, from `SHELL`: `zsh`, `bash`, ...
_shell(): String {
    var shell = os.environment("SHELL").value_or("");
    return Path(shell).file_name().value_or("");
}

# The user's PATH on Windows is read and set through PowerShell, which
# every Windows has, as the environment variable `PEPPER_USER_PATH` for
# writing so no quoting is involved.
_add_to_windows_path(bin: Path): Result<void> {
    var current = _windows_user_path()?;
    if (path_lists(current, bin.to_string(), true)) {
        _say("open a new terminal to run pepper");
        return Result<void>.ok();
    }
    var entries = Array<String>();
    for (var entry in current.split(";")) {
        if (!entry.is_empty) {
            entries.append(entry);
        }
    }
    entries.append(bin.to_string());
    _set_windows_user_path(";".join(entries))?;
    _say($"added {bin.to_string()} to your PATH; open a new terminal to run pepper");
    return Result<void>.ok();
}

_remove_from_windows_path(bin: Path): Result<String> {
    var current = _windows_user_path()?;
    if (!path_lists(current, bin.to_string(), true)) {
        return Result<String>.ok("");
    }
    var wanted = _path_entry(bin.to_string(), true);
    var entries = Array<String>();
    for (var entry in current.split(";")) {
        if (!entry.is_empty and _path_entry(entry, true) != wanted) {
            entries.append(entry);
        }
    }
    _set_windows_user_path(";".join(entries))?;
    return Result<String>.ok($"removed {bin.to_string()} from your PATH\n");
}

_windows_user_path(): Result<String> {
    var ran = process
        .Command("powershell")
        .arguments(
            ["-NoProfile", "-NonInteractive", "-Command", "[Environment]::GetEnvironmentVariable('Path', 'User')"]
        )
        .run();
    if (ran.is_err() or !ran.value().status.success()) {
        return Result<String>.Err("cannot read your PATH with PowerShell");
    }
    return Result<String>.ok(ran.value().stdout.trim());
}

_set_windows_user_path(value: String): Result<void> {
    var ran = process
        .Command("powershell")
        .arguments(
            [
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                "[Environment]::SetEnvironmentVariable('Path', $env:PEPPER_USER_PATH, 'User')"
            ]
        )
        .environment("PEPPER_USER_PATH", value)
        .run();
    if (ran.is_err() or !ran.value().status.success()) {
        return Result<void>.Err("cannot set your PATH with PowerShell");
    }
    return Result<void>.ok();
}

# ── Prerequisites ────────────────────────────────────────────────────────────

# Offers to install what linking a program needs and the `tls` module
# loads, beyond the clang the check program finds missing.
_check_prerequisites(assume_yes: bool) {
    var system = os.system_os();
    if (system == os.OperatingSystem.Mac) {
        _check_command_line_tools(assume_yes);
        _check_mac_openssl(assume_yes);
        return;
    }
    if (system == os.OperatingSystem.Windows) {
        _check_msvc_tools(assume_yes);
        return;
    }
    _check_linux_openssl();
}

# Xcode's command line tools: the SDK and linker clang links with.
_check_command_line_tools(assume_yes: bool) {
    if (_succeeds(process.Command("xcode-select").argument("-p"))) {
        return;
    }
    _say("Linking programs needs Xcode's command line tools, which are not installed.");
    if (!_ask("Install them now (xcode-select --install opens an installer window)?", assume_yes)) {
        _warn("install them before building a program: xcode-select --install");
        return;
    }
    _run_inherited(process.Command("xcode-select").argument("--install"));
    _warn("finish the command line tools' installer, then run 'pepper build' as usual");
}

# OpenSSL 3, which the `tls` module loads when a program uses it.
_check_mac_openssl(assume_yes: bool) {
    for (var candidate in [
        "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib",
        "/usr/local/opt/openssl@3/lib/libssl.3.dylib",
        "/opt/local/lib/libssl.3.dylib"
    ]) {
        if (Path(candidate).is_file()) {
            return;
        }
    }
    var question = "Programs that use the 'tls' module need OpenSSL 3. Install it with 'brew install openssl@3'?";
    if (process.find_executable("brew").is_empty() or !_ask(question, assume_yes)) {
        _say("note: programs that use the 'tls' module need OpenSSL 3: brew install openssl@3");
        return;
    }
    if (!_run_inherited(process.Command("brew").arguments(["install", "openssl@3"]))) {
        _warn("'brew install openssl@3' failed");
    }
}

_check_linux_openssl() {
    for (var ldconfig in ["ldconfig", "/sbin/ldconfig"]) {
        var ran = process.Command(ldconfig).argument("-p").run();
        if (ran.is_ok() and ran.value().stdout.contains("libssl.so.3")) {
            return;
        }
    }
    _say(
        "note: programs that use the 'tls' module need OpenSSL 3 (libssl.so.3), which was not found; install your distribution's OpenSSL 3 package to use it"
    );
}

# The MSVC x64 tools of a Visual Studio or Build Tools install, which carry
# the libraries (and with them the Windows SDK) clang links with.
_check_msvc_tools(assume_yes: bool) {
    var program_files = os.environment("ProgramFiles(x86)").value_or("C:\\Program Files (x86)");
    var vswhere = Path(program_files).join("Microsoft Visual Studio").join("Installer").join("vswhere.exe");
    var found = process
        .Command(vswhere.to_string())
        .arguments(
            [
                "-products",
                "*",
                "-requires",
                "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                "-property",
                "installationPath"
            ]
        )
        .run();
    if (found.is_ok() and !found.value().stdout.trim().is_empty) {
        return;
    }
    var question = "Linking needs the MSVC libraries and Windows SDK. Install the Visual Studio Build Tools C++ workload with winget?";
    if (process.find_executable("winget.exe").is_empty() or !_ask(question, assume_yes)) {
        _warn(
            "install the Visual Studio Build Tools with the \"Desktop development with C++\" workload before building a program: https://visualstudio.microsoft.com/visual-cpp-build-tools/"
        );
        return;
    }
    _run_inherited(
        process.Command(
            "winget"
        ).arguments(
            [
                "install",
                "--id",
                "Microsoft.VisualStudio.2022.BuildTools",
                "--exact",
                "--accept-package-agreements",
                "--accept-source-agreements",
                "--override",
                "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
            ]
        )
    );
}

# Offers to install clang, which the check program found missing, and
# returns whether it did.
_install_clang(assume_yes: bool): bool {
    var install = _clang_install_command();
    if (install.is_empty) {
        _warn("install clang (on Windows, LLVM) with your package manager, then run 'pepper build' as usual");
        return false;
    }
    var shown = " ".join(install);
    if (!_ask($"Linking programs needs clang, which is not installed. Install it with '{shown}'?", assume_yes)) {
        _warn($"install it before building a program: {shown}");
        return false;
    }
    var command = process.Command(install[0]);
    for (var index in 1..install.count) {
        command.argument(install[index]);
    }
    if (!_run_inherited(command)) {
        _warn($"'{shown}' failed; install clang yourself");
        return false;
    }
    return true;
}

# The command that installs clang (and on Linux the C library's development
# files) with this machine's package manager, run through sudo when not
# root; empty when it has none this knows.
_clang_install_command(): Array<String> {
    if (toolchain.is_windows()) {
        if (process.find_executable("winget.exe").is_value()) {
            return [
                "winget",
                "install",
                "--id",
                "LLVM.LLVM",
                "--exact",
                "--accept-package-agreements",
                "--accept-source-agreements"
            ];
        }
        if (process.find_executable("scoop.cmd").is_value()) {
            return ["scoop.cmd", "install", "llvm"];
        }
        return Array<String>();
    }
    var managers = [
        ["apt-get", "install", "-y", "clang", "build-essential"],
        ["dnf", "install", "-y", "clang", "gcc", "glibc-devel"],
        ["yum", "install", "-y", "clang", "gcc", "glibc-devel"],
        ["pacman", "-S", "--needed", "--noconfirm", "clang", "gcc"],
        ["zypper", "install", "-y", "clang", "gcc", "glibc-devel"]
    ];
    for (var manager in managers) {
        if (process.find_executable(manager[0]).is_empty()) {
            continue;
        }
        if (os.is_elevated()) {
            return manager;
        }
        var command = ["sudo"];
        for (var word in manager) {
            command.append(word);
        }
        return command;
    }
    return Array<String>();
}

# ── The check program ────────────────────────────────────────────────────────

# Builds and runs a small program with the home's `pepper`, from an empty
# folder. When the build finds no clang, it offers to install one and tries
# again.
_check_install(home: toolchain.Home, options: SetupOptions): Result<void> {
    var work = os.temp_directory().join($"pepper-setup-{process.id()}");
    Directory.remove_all(work);
    var created = Directory.create_all(work);
    if (created.is_err()) {
        return Result<void>.Err($"cannot create {work.to_string()}: {created.error().message}");
    }
    var checked = _build_and_run(home, work, options);
    Directory.remove_all(work);
    return checked;
}

_build_and_run(home: toolchain.Home, work: Path, options: SetupOptions): Result<void> {
    File.write_text(work.join("hello.pep"), "main(): int {\n    print(\"Pepper is installed.\");\n    return 0;\n}\n");
    var program = work.join("hello" + toolchain.executable_suffix());
    var build = process
        .Command(home.bin.join("pepper" + toolchain.executable_suffix()).to_string())
        .arguments(["build", "hello.pep", "-o", program.to_string()])
        .working_directory(work);
    var built = build.run();
    if (built.is_err()) {
        return Result<void>.Err($"cannot run {home.bin.to_string()}/pepper: {built.error().message}");
    }
    var output = built.value().stdout + built.value().stderr;
    var no_clang = output.contains("no clang found");
    if (!built.value().status.success() and no_clang and options.prerequisites and _install_clang(options.assume_yes)) {
        built = build.run();
        if (built.is_ok()) {
            output = built.value().stdout + built.value().stderr;
        }
    }
    if (built.is_err() or !built.value().status.success()) {
        File.stderr().write_all(output);
        return Result<void>.Err(
            $"Pepper is installed in {home.root.to_string()}, but could not build a program; see the error above"
        );
    }
    var ran = process.Command(program.to_string()).working_directory(work).run();
    if (ran.is_err() or !ran.value().status.success()) {
        return Result<void>.Err(
            $"Pepper is installed in {home.root.to_string()}, but the program it built did not run"
        );
    }
    _say(ran.value().stdout.trim());
    return Result<void>.ok();
}

# ── Talking to the user ──────────────────────────────────────────────────────

_say(message: String) {
    File.stdout().write_all($"pep-install: {message}\n");
}

_warn(message: String) {
    File.stderr().write_all($"pep-install: warning: {message}\n");
}

# Asks a yes/no question on the terminal, which may not be standard input
# (a script piped into sh is). Yes with `assume_yes`; no when there is no
# terminal to ask on.
_ask(question: String, assume_yes: bool): bool {
    if (assume_yes) {
        return true;
    }
    var terminal = File.open(Path(toolchain.is_windows() ? "CONIN$" : "/dev/tty"));
    if (terminal.is_err()) {
        return false;
    }
    File.stdout().write_all($"pep-install: {question} [Y/n] ");
    for (var line in terminal.value().lines()) {
        if (line.is_err()) {
            return false;
        }
        var answer = line.value().trim().lower();
        return answer.is_empty or answer == "y" or answer == "yes";
    }
    return false;
}

_succeeds(command: process.Command): bool {
    var ran = command.run();
    return ran.is_ok() and ran.value().status.success();
}

# Runs `command` with this program's standard streams, and returns whether
# it succeeded.
_run_inherited(command: process.Command): bool {
    var started = command
        .stdin(process.Stream.Inherit)
        .stdout(process.Stream.Inherit)
        .stderr(process.Stream.Inherit)
        .spawn();
    if (started.is_err()) {
        return false;
    }
    var status = started.value().wait();
    return status.is_ok() and status.value().success();
}
