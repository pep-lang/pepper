# pep-profile: profiles a program and writes a flame graph of where it
# spends its time, using a sampling profiler that is already installed.
#
#     pep-profile main.pep                   # build it, profile it, write main.svg
#     pep-profile ./server -- --port 8080    # an executable, with its arguments
#     pep-profile --pid 4242 --duration 10   # a running process, for 10 seconds
#     pep-profile --input perf.data          # draw a recording made earlier
#
# A `.pep` file is first built with `pep-build -O -g --frame-pointers`, so
# the profiler can walk the optimized program's stack and the frames have
# names. The recording comes from samply when it is installed, else perf
# (Linux) or sample (macOS); llvm-symbolizer, when found, names the
# functions inlined into each frame from the debug info. The flame graph is
# drawn by a renderer built in, or by inferno or flamegraph.pl
# (`--renderer`).
#
# Build it from the repository root with the tools folder on the import
# path:
#
#     pepper build -I tools tools/pep-profile/main.pep -o pep-profile

import cli;
import [Directory, File, Path] from io;
import json;
import os;
import process;
import "flame";
import "profile";
import "symbols";

# The release this tool belongs to. `pep-doc check` keeps it equal to the
# version in VERSION.
version(): String {
    return "0.9.2";
}

# How long to record a process given by `--pid` when `--duration` is not.
const DEFAULT_ATTACH_SECONDS = 10;

main(args: String[]): int {
    var parser = cli.Parser(
        "pep-profile", "Profiles a program and writes a flame graph of where it spends its time.", version = version()
    );
    var output = parser.option(
        "output", "o", "the flame graph to write (default: the program's name with .svg)", value_name = "FILE"
    );
    var frequency = parser.option("frequency", "F", "samples per second", value_name = "HZ", default_value = "999");
    var duration = parser.option("duration", "d", "stop recording after this many seconds", value_name = "SECONDS");
    var pid = parser.option("pid", "p", "record the running process with this id instead", value_name = "PID");
    var profiler_name = parser.option(
        "profiler", help = "the profiler to record with: samply, perf, sample, or a path to one", value_name = "NAME"
    );
    var renderer = parser.option(
        "renderer",
        help = "what draws the flame graph: builtin (the default), inferno or flamegraph.pl",
        value_name = "NAME"
    );
    var raw = parser.option(
        "raw", help = "also keep the profiler's own recording, for other viewers", value_name = "FILE"
    );
    var folded = parser.option("folded", help = "also write the folded stacks", value_name = "FILE");
    var input = parser.option(
        "input", "i", "draw a recording made earlier instead of recording one", value_name = "FILE"
    );
    var title = parser.option("title", help = "the flame graph's title", value_name = "TEXT");
    var symbolizer_name = parser.option(
        "symbolizer", help = "the llvm-symbolizer to name frames with, or none", value_name = "PATH"
    );
    var imports = parser.multiple("import-path", "I", "a directory pep-build searches for imports", value_name = "DIR");
    var lines = parser.flag("lines", "l", "end each frame's name with its file and line");
    var idle = parser.flag("idle", help = "keep samples of threads that were waiting, not running (samply)");
    var open = parser.flag("open", help = "open the flame graph when it is written");
    var command = parser.positionals(
        "program", "the .pep file or executable to profile, then its arguments (after --, if any start with -)"
    );
    if (!parser.parse(args)) {
        return 2;
    }
    var options = Options();
    options.output = output.value_or("");
    options.duration = duration.value_or("");
    options.pid = pid.value_or("");
    options.profiler = profiler_name.value_or("");
    options.raw = raw.value_or("");
    options.folded = folded.value_or("");
    options.input = input.value_or("");
    options.title = title.value_or("");
    options.lines = lines.is_set;
    options.idle = idle.is_set;
    options.imports = imports.values();
    options.command = command.values();
    var hz = uint.parse(frequency.value());
    if (hz.is_empty() or hz.value() == 0) {
        return usage_error(parser, $"'--frequency' must be a positive number, not '{frequency.value()}'");
    }
    options.frequency = hz.value();
    if (!options.duration.is_empty and (uint.parse(options.duration).is_empty() or options.duration == "0")) {
        return usage_error(parser, $"'--duration' must be a positive number of seconds, not '{options.duration}'");
    }
    if (!options.pid.is_empty and ulong.parse(options.pid).is_empty()) {
        return usage_error(parser, $"'--pid' must be a process id, not '{options.pid}'");
    }
    var sources = (options.input.is_empty ? 0 : 1)
        + (options.pid.is_empty ? 0 : 1)
        + (options.command.is_empty ? 0 : 1);
    if (sources != 1) {
        return usage_error(parser, "give one of: a program to run, '--pid', or '--input'");
    }
    var render_with = renderer.value_or("").is_empty ? "builtin" : renderer.value_or("");
    if (render_with != "builtin" and render_with != "inferno" and render_with != "flamegraph.pl") {
        return usage_error(parser, $"unknown renderer '{render_with}': use builtin, inferno or flamegraph.pl");
    }
    if (options.output.is_empty) {
        options.output = default_output(options) + ".svg";
    }
    if (options.title.is_empty) {
        options.title = "Flame graph: " + default_output(options);
    }

    var scratch = Directory.temp().join($"pep-profile-{process.id()}");
    var made = Directory.create_all(scratch);
    if (made.is_err()) {
        return fail($"cannot create '{scratch.to_string()}': {made.error().message}");
    }
    var status = profile_and_draw(options, render_with, scratch, symbolizer_name.value_or(""));
    Directory.remove_all(scratch);
    if (status != 0) {
        return status;
    }
    if (open.is_set) {
        open_file(options.output);
    }
    return 0;
}

# What to profile and where the results go, from the command line.
struct Options {
    var output: String = "";
    var frequency: uint = 999;
    var duration: String = "";
    var pid: String = "";
    var profiler: String = "";
    var raw: String = "";
    var folded: String = "";
    var input: String = "";
    var title: String = "";
    var lines: bool = false;
    var idle: bool = false;
    var imports: Array<String> = __null;
    var command: Array<String> = __null;

    construct() {
        this.imports = Array<String>();
        this.command = Array<String>();
    }
}

# Records (or reads) the profile, names its frames, and writes the flame
# graph and whatever else was asked for. Returns the exit status.
profile_and_draw(options: Options, render_with: String, scratch: Path, symbolizer_name: String): int {
    var stacks = "";
    if (!options.input.is_empty) {
        var read = read_recording(options.input, options.profiler, options.lines, options.idle, symbolizer_name);
        if (read.is_err()) {
            return fail(read.error().message);
        }
        stacks = read.value();
    } else {
        var recorded = record(options, scratch);
        if (recorded.is_err()) {
            return fail(recorded.error().message);
        }
        var recording = recorded.value();
        if (!options.raw.is_empty) {
            var copied = File.copy(Path(recording), Path(options.raw));
            if (copied.is_err()) {
                return fail($"cannot write '{options.raw}': {copied.error().message}");
            }
            var symbols = Path(sidecar_path(recording));
            if (symbols.is_file()) {
                File.copy(symbols, Path(sidecar_path(options.raw)));
            }
        }
        var read = read_recording(recording, options.profiler, options.lines, options.idle, symbolizer_name);
        if (read.is_err()) {
            return fail(read.error().message);
        }
        stacks = read.value();
    }
    if (stacks.trim().is_empty) {
        return fail("the profiler recorded no samples");
    }
    if (!options.folded.is_empty) {
        var written = File.write_text(Path(options.folded), stacks);
        if (written.is_err()) {
            return fail($"cannot write '{options.folded}': {written.error().message}");
        }
    }
    var svg = render(stacks, options.title, render_with, scratch);
    if (svg.is_err()) {
        return fail(svg.error().message);
    }
    var written = File.write_text(Path(options.output), svg.value());
    if (written.is_err()) {
        return fail($"cannot write '{options.output}': {written.error().message}");
    }
    var samples = build_tree(stacks).total;
    File.stderr().write_all($"pep-profile: wrote {options.output} ({samples} samples)\n");
    return 0;
}

# The name results take by default: the program's file stem, or the
# process id, or the input's stem.
default_output(options: Options): String {
    var named = !options.input.is_empty ? options.input : !options.command.is_empty ? options.command[0] : "";
    if (named.is_empty) {
        return $"pid-{options.pid}";
    }
    var stem = Path(named).file_stem();
    return stem.is_value() ? stem.value() : "profile";
}

# Records the program or process with the profiler options name, and
# returns the recording's path.
record(options: Options, scratch: Path): Result<String> {
    var profiler = find_profiler(options.profiler);
    if (profiler.is_err()) {
        return Result<String>.Err(profiler.error().message);
    }
    var (kind, program) = profiler.value();
    # samply records Windows' ETW events, which only an elevated process
    # may: without one, it waits on a UAC prompt and then fails.
    if (kind == "samply" and os.system_os() == os.OperatingSystem.Windows and !os.is_elevated()) {
        return Result<String>.Err(
            "samply needs administrator rights on Windows: run pep-profile from an Administrator terminal (\"Run as administrator\")"
        );
    }
    var command = Array<String>();
    if (options.pid.is_empty) {
        var executable = options.command[0];
        if (executable.ends_with(".pep")) {
            var built = build(executable, options.imports, scratch);
            if (built.is_err()) {
                return Result<String>.Err(built.error().message);
            }
            executable = built.value();
        } else if (!executable.contains("/") and !executable.contains("\\") and Path(executable).is_file()) {
            # A file in this directory, as the user named it, not a command
            # on the PATH.
            executable = "." + Path.separator() + executable;
        }
        command.append(executable);
        for (var index in 1..options.command.count) {
            command.append(options.command[index]);
        }
    }
    var seconds = options.duration;
    if (seconds.is_empty and !options.pid.is_empty) {
        seconds = to_string(DEFAULT_ATTACH_SECONDS);
    }
    if (kind == "samply") {
        return record_samply(program, options, seconds, command, scratch);
    }
    if (kind == "perf") {
        return record_perf(program, options, seconds, command, scratch);
    }
    return record_sample(program, options, seconds, command, scratch);
}

# Builds `source` for profiling, optimized with debug info and frame
# pointers, and returns the executable's path.
build(source: String, imports: Array<String>, scratch: Path): Result<String> {
    var compiler = process.find_companion("pep-build");
    if (compiler.is_empty()) {
        return Result<String>.Err("cannot find pep-build next to pep-profile or on the PATH to build '" + source + "'");
    }
    var stem = Path(source).file_stem();
    var name = (stem.is_value() ? stem.value() : "program") + executable_suffix();
    var executable = scratch.join(name).to_string();
    var arguments = Array<String>();
    arguments.append(source);
    for (var directory in imports) {
        arguments.append("-I");
        arguments.append(directory);
    }
    arguments.append("-O");
    arguments.append("-g");
    arguments.append("--frame-pointers");
    arguments.append("-o");
    arguments.append(executable);
    var child = process.Command(compiler.value().to_string()).arguments(arguments).spawn();
    if (child.is_err()) {
        return Result<String>.Err($"cannot run pep-build: {child.error().message}");
    }
    var status = child.value().wait();
    if (status.is_err() or !status.value().success()) {
        return Result<String>.Err($"pep-build could not build '{source}'");
    }
    return Result<String>.Ok(executable);
}

# Records with samply, which keeps every stack with its timing in the
# Firefox Profiler's format.
record_samply(
    samply: String, options: Options, seconds: String, command: Array<String>, scratch: Path
): Result<String> {
    var recording = scratch.join("profile.json").to_string();
    var arguments = Array<String>();
    arguments.append("record");
    arguments.append("--save-only");
    arguments.append("--no-open");
    arguments.append("--unstable-presymbolicate");
    arguments.append("--rate");
    arguments.append(to_string(options.frequency));
    arguments.append("--output");
    arguments.append(recording);
    if (!seconds.is_empty) {
        arguments.append("--duration");
        arguments.append(seconds);
    }
    if (!options.pid.is_empty) {
        arguments.append("--pid");
        arguments.append(options.pid);
    } else {
        arguments.append("--");
        arguments.append_all(command);
    }
    return run_profiler(samply, arguments, recording);
}

# Records with perf, walking each sample's stack by frame pointers.
record_perf(perf: String, options: Options, seconds: String, command: Array<String>, scratch: Path): Result<String> {
    var recording = scratch.join("perf.data").to_string();
    var arguments = Array<String>();
    arguments.append("record");
    arguments.append("--call-graph=fp");
    arguments.append("--all-user");
    arguments.append("-F");
    arguments.append(to_string(options.frequency));
    arguments.append("-o");
    arguments.append(recording);
    if (!options.pid.is_empty) {
        arguments.append("-p");
        arguments.append(options.pid);
        arguments.append("--");
        arguments.append("sleep");
        arguments.append(seconds);
    } else {
        arguments.append("--");
        if (!seconds.is_empty) {
            # perf records until the program ends: `timeout` ends it.
            arguments.append("timeout");
            arguments.append(seconds);
        }
        arguments.append_all(command);
    }
    return run_profiler(perf, arguments, recording);
}

# Records with macOS `sample`: starts the program, then samples it until it
# exits or the duration is up.
record_sample(
    sample: String, options: Options, seconds: String, command: Array<String>, scratch: Path
): Result<String> {
    var recording = scratch.join("sample.txt").to_string();
    var interval = 1000 / options.frequency;
    var child = Optional<process.Child>.Empty;
    var target = options.pid;
    if (target.is_empty) {
        var rest = Array<String>();
        for (var index in 1..command.count) {
            rest.append(command[index]);
        }
        var started = process.Command(command[0]).arguments(rest).spawn();
        if (started.is_err()) {
            return Result<String>.Err($"cannot start '{command[0]}': {started.error().message}");
        }
        child = Optional<process.Child>.Value(started.value());
        target = to_string(started.value().id());
    }
    var arguments = Array<String>();
    arguments.append(target);
    arguments.append(seconds.is_empty ? "3600" : seconds);
    arguments.append(to_string(interval > 0 ? interval : 1));
    arguments.append("-mayDie");
    arguments.append("-file");
    arguments.append(recording);
    var recorded = run_profiler(sample, arguments, recording);
    if (child.is_value()) {
        if (!seconds.is_empty) {
            child.value().kill();
        }
        child.value().wait();
    }
    return recorded;
}

# Runs a profiler, which shares this program's terminal, and returns
# `recording` once it has written it.
run_profiler(program: String, arguments: Array<String>, recording: String): Result<String> {
    var child = process.Command(program).arguments(arguments).spawn();
    if (child.is_err()) {
        return Result<String>.Err($"cannot run '{program}': {child.error().message}");
    }
    var status = child.value().wait();
    if (status.is_err()) {
        return Result<String>.Err($"'{program}' failed: {status.error().message}");
    }
    if (!Path(recording).is_file()) {
        return Result<String>.Err($"'{program}' did not record a profile ({status.value().to_string()})");
    }
    return Result<String>.Ok(recording);
}

# The profiler to record with, as its kind (samply, perf or sample) and
# path: `requested` when given, else the first of those installed that
# this system has.
find_profiler(requested: String): Result<(String, String)> {
    if (!requested.is_empty) {
        var kind = base_name(requested).lower().replace(".exe", "");
        if (kind != "samply" and kind != "perf" and kind != "sample" and !kind.starts_with("perf")) {
            return Result<(String, String)>.Err($"unknown profiler '{requested}': use samply, perf or sample");
        }
        kind = kind.starts_with("perf") ? "perf" : kind;
        var found = kind == "perf" ? find_perf(requested) : process.find_executable(requested);
        if (found.is_empty()) {
            return Result<(String, String)>.Err($"cannot find the profiler '{requested}'");
        }
        return Result<(String, String)>.Ok((kind, found.value().to_string()));
    }
    var samply = process.find_executable("samply");
    if (samply.is_value()) {
        return Result<(String, String)>.Ok(("samply", samply.value().to_string()));
    }
    var system = os.system_os();
    if (system == os.OperatingSystem.Linux) {
        var perf = find_perf("perf");
        if (perf.is_value()) {
            return Result<(String, String)>.Ok(("perf", perf.value().to_string()));
        }
    }
    if (system == os.OperatingSystem.Mac) {
        var sample = process.find_executable("sample");
        if (sample.is_value()) {
            return Result<(String, String)>.Ok(("sample", sample.value().to_string()));
        }
    }
    var message = "no supported profiler is installed; install samply (cargo install --locked samply)";
    if (system == os.OperatingSystem.Linux) {
        message = message + ", or perf (the linux-tools package for your kernel)";
    }
    return Result<(String, String)>.Err(message);
}

# A perf that runs: `name` when it answers `--version`, else (as Ubuntu's
# `perf` wrapper fails when no perf matches the running kernel) the newest
# under /usr/lib/linux-tools.
find_perf(name: String): Path? {
    var found = process.find_executable(name);
    if (found.is_value() and answers_version(found.value())) {
        return found;
    }
    var tools = Directory.open(Path("/usr/lib/linux-tools"));
    if (tools.is_err()) {
        return Optional<Path>.Empty;
    }
    var listed = tools.value().entries();
    if (listed.is_err()) {
        return Optional<Path>.Empty;
    }
    var entries = listed.value();
    entries.sort((a, b) => b.name.compare(a.name));
    for (var entry in entries) {
        var candidate = entry.path.join("perf");
        if (process.is_executable(candidate) and answers_version(candidate)) {
            return Optional<Path>.Value(candidate);
        }
    }
    return Optional<Path>.Empty;
}

# Whether `program --version` says it is perf.
answers_version(program: Path): bool {
    var ran = process.Command(program.to_string()).argument("--version").run();
    return ran.is_ok() and ran.value().status.success() and ran.value().stdout.starts_with("perf version");
}

# The folded stacks of a recording: a samply profile, a perf.data file,
# `perf script` text, a `sample` report, or folded stacks themselves,
# told apart by what the file holds. Without `idle`, a samply profile's
# samples of threads that used no CPU are left out.
read_recording(path: String, profiler: String, lines: bool, idle: bool, symbolizer_name: String): Result<String> {
    var bytes = File.read_bytes(Path(path));
    if (bytes.is_err()) {
        return Result<String>.Err($"cannot read '{path}': {bytes.error().message}");
    }
    var symbolizer = Optional<Symbolizer>.Empty;
    var symbolizer_path = symbolizer_name == "none" ? Optional<String>.Empty : find_symbolizer(symbolizer_name);
    if (symbolizer_path.is_value()) {
        symbolizer = Optional<Symbolizer>.Value(Symbolizer(symbolizer_path.value()));
    } else if (!symbolizer_name.is_empty and symbolizer_name != "none") {
        return Result<String>.Err($"cannot find the symbolizer '{symbolizer_name}'");
    }
    var data = bytes.value();
    if (data.count >= 8 and starts_with_bytes(data, "PERFILE2")) {
        var perf = find_perf(profiler.is_empty ? "perf" : profiler);
        if (perf.is_empty()) {
            return Result<String>.Err(
                $"'{path}' is a perf recording, and reading it needs perf, which cannot be found"
            );
        }
        var arguments = Array<String>();
        arguments.append("script");
        arguments.append("-F");
        arguments.append("ip,sym,symoff,dso");
        arguments.append("-i");
        arguments.append(path);
        var ran = process.Command(perf.value().to_string()).arguments(arguments).stderr(process.Stream.Null).run();
        if (ran.is_err() or !ran.value().status.success()) {
            return Result<String>.Err($"perf could not read '{path}'");
        }
        return Result<String>.Ok(symbolized(read_perf_script(ran.value().stdout), symbolizer, lines));
    }
    var text = File.read_to_string(Path(path));
    if (text.is_err()) {
        return Result<String>.Err($"'{path}' is not a recording pep-profile can read");
    }
    var content = text.value();
    var start = content.trim_start();
    if (start.starts_with("{")) {
        var document = json.parse(content);
        if (document.is_err()) {
            return Result<String>.Err($"'{path}' is not valid JSON: {document.error().message}");
        }
        var symbols = json.JsonValue.Null;
        var sidecar = File.read_to_string(Path(sidecar_path(path)));
        if (sidecar.is_ok()) {
            var parsed = json.parse(sidecar.value());
            if (parsed.is_ok()) {
                symbols = parsed.value();
            }
        }
        var profile = read_samply(document.value(), symbols, idle);
        if (profile.is_err()) {
            return Result<String>.Err($"'{path}': {profile.error().message}");
        }
        return Result<String>.Ok(symbolized(profile.value(), symbolizer, lines));
    }
    if (content.contains("\nCall graph:\n") or content.starts_with("Call graph:")) {
        return Result<String>.Ok(symbolized(read_sample_report(content), symbolizer, lines));
    }
    if (is_perf_script(content)) {
        return Result<String>.Ok(symbolized(read_perf_script(content), symbolizer, lines));
    }
    if (is_folded(content)) {
        return Result<String>.Ok(content);
    }
    return Result<String>.Err($"'{path}' is not a recording pep-profile can read");
}

# The folded stacks of `profile`, its frames named.
symbolized(profile: Profile, symbolizer: Symbolizer?, lines: bool): String {
    profile.symbolize(symbolizer, lines);
    return profile.fold();
}

# Whether `data` starts with the bytes of `text`.
starts_with_bytes(data: Array<u8>, text: String): bool {
    var expected = text.bytes();
    for (var index in 0..expected.count) {
        if (data[index] != expected[index]) {
            return false;
        }
    }
    return true;
}

# Whether `text` looks like `perf script` output: its frame lines are
# indented with a tab.
is_perf_script(text: String): bool {
    for (var line in text.lines()) {
        if (line.starts_with("\t")) {
            return true;
        }
    }
    return false;
}

# Whether every line of `text` is a folded stack: names, a space, a count.
is_folded(text: String): bool {
    var any = false;
    for (var line in text.lines()) {
        if (line.trim().is_empty) {
            continue;
        }
        var space = line.rfind(" ");
        if (space <= 0
            or long.parse(
                line.substr_bytes((space + 1) as ulong, line.size - (space + 1) as ulong).trim()
            ).is_empty()) {
            return false;
        }
        any = true;
    }
    return any;
}

# Where samply keeps a profile's symbols: `profile.json` has
# `profile.syms.json`.
sidecar_path(recording: String): String {
    var stem = recording.ends_with(".json") ? recording.substr_bytes(0, recording.size - 5) : recording;
    return stem + ".syms.json";
}

# The flame graph of `stacks`, drawn by `renderer`.
render(stacks: String, title: String, renderer: String, scratch: Path): Result<String> {
    if (renderer == "builtin") {
        return Result<String>.Ok(render_svg(stacks, title));
    }
    var program = renderer == "inferno" ? "inferno-flamegraph" : "flamegraph.pl";
    var found = process.find_executable(program);
    if (found.is_empty()) {
        return Result<String>.Err($"cannot find '{program}' on the PATH");
    }
    var input = scratch.join("stacks.folded");
    var written = File.write_text(input, stacks);
    if (written.is_err()) {
        return Result<String>.Err($"cannot write '{input.to_string()}': {written.error().message}");
    }
    var arguments = Array<String>();
    arguments.append("--title");
    arguments.append(title);
    arguments.append(input.to_string());
    var ran = process.Command(found.value().to_string()).arguments(arguments).run();
    if (ran.is_err() or !ran.value().status.success()) {
        return Result<String>.Err($"'{program}' could not draw the flame graph");
    }
    return Result<String>.Ok(ran.value().stdout);
}

# Opens `path` with the system's viewer for it.
open_file(path: String) {
    var system = os.system_os();
    var command = process.Command(system == os.OperatingSystem.Mac ? "open" : "xdg-open").argument(path);
    if (system == os.OperatingSystem.Windows) {
        command = process.Command("cmd").argument("/c").argument("start").argument("").argument(path);
    }
    var ran = command.run();
    if (ran.is_err() or !ran.value().status.success()) {
        File.stderr().write_all($"pep-profile: warning: cannot open '{path}'\n");
    }
}

executable_suffix(): String {
    return os.system_os() == os.OperatingSystem.Windows ? ".exe" : "";
}

# Reports a usage error and returns the usage-error status.
usage_error(parser: cli.Parser, message: String): int {
    File.stderr().write_all($"pep-profile: error: {message}\n{parser.usage()}\n");
    return 2;
}

# Reports an error and returns the failure status.
fail(message: String): int {
    File.stderr().write_all($"pep-profile: error: {message}\n");
    return 1;
}
