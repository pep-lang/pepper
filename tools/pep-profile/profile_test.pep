# pep-profile end to end, the one beside the test program or on the PATH
# (scripts/pepper-tests.sh builds it): reading each recording format it
# supports into folded stacks with readable names, and drawing them with
# the built-in renderer. The recordings in `testdata/` are written by
# hand, so these tests need no profiler; one profiles a real program when
# samply or a working perf is installed. Run with `-I tools`.

import [Path] from io;
import os;
import process;
import [TempFolder] from testing;
import [
    build_program, expect_contains, expect_exit, expect_starts_with, read_file, run, tool, write_file
] from tool_testing;
import toolchain;

# The recording `name` in `testdata/`.
recording(name: String): Path {
    return Path("pep-profile").join("testdata").join(name);
}

# The command that runs pep-profile with `arguments`.
pep_profile(arguments: Array<String>): process.Command {
    return process.Command(tool("pep-profile").to_string()).arguments(arguments);
}

# The folded stacks pep-profile reads from the recording `name`, with no
# symbolizer, so names come from the recording alone, and with `extra`
# arguments.
folded(name: String, extra: Array<String> = Array<String>()): String {
    var folder = TempFolder("pep_profile_folded");
    var stacks = folder.path.join("stacks.folded");
    var output = run(
        pep_profile(
            ["--input", recording(name).to_string(), "--symbolizer", "none"]
        ).arguments(["--folded", stacks.to_string(), "-o", folder.path.join("graph.svg").to_string()]).arguments(extra)
    );
    expect_exit(output, 0);
    return read_file(stacks);
}

[Test]
folded_stacks_draw_as_a_flame_graph() {
    var folder = TempFolder("pep_profile_draw");
    var svg = folder.path.join("out.svg");
    var output = run(
        pep_profile(["-i", recording("stacks.folded").to_string(), "-o", svg.to_string(), "--title", "A & B"])
    );
    expect_exit(output, 0);
    expect_contains(output.stderr, "(8 samples)");
    var drawn = read_file(svg);
    expect_starts_with(drawn, "<?xml");
    # The title, escaped.
    expect_contains(drawn, ">A &amp; B</text>");
    expect_contains(drawn, "<title>all (8 samples, 100.00%)</title>");
    expect_contains(drawn, "<title>main (8 samples, 100.00%)</title>");
    expect_contains(drawn, "<title>work (4 samples, 50.00%)</title>");
    expect_contains(drawn, "<title>Box&lt;int&gt;.get (3 samples, 37.50%)</title>");
    expect_contains(drawn, "<title>other (4 samples, 50.00%)</title>");
}

[Test]
perf_script_frames_are_demangled_and_folded() {
    # `perf script -F ip,sym,symoff,dso`: the innermost frame first; the
    # program is not on this machine, so the symbols name the frames.
    expect_equal(
        folded("perf.txt"),
        "__libc_start_main;main;closure #3 in geo/shapes 1\n"
            + "__libc_start_main;main;work 1\n"
            + "__libc_start_main;main;work;Array<int>.count 1\n"
            + "area;[unknown] 1\n"
    );
}

[Test]
samply_profiles_name_frames_from_their_symbol_file() {
    # Two samples of one thread: stacks 2 (main > work > get) and 1
    # (main > work), named by `samply.syms.json` beside the profile;
    # frame 2's address no symbol covers, so it keeps the profile's own
    # name for it.
    expect_equal(folded("samply.json"), "main;work 1\nmain;work;[program] 2\n");
}

[Test]
samples_of_waiting_threads_are_left_out_unless_idle() {
    # A working thread (two samples that used CPU, one that did not) and a
    # thread pool's idle worker, which samply records as one sample
    # weighted by how long it waited, with no CPU used.
    expect_equal(folded("samply_idle.json"), "main;work 2\n");
    expect_equal(
        folded("samply_idle.json", ["--idle"]),
        "RtlUserThreadStart;NtWaitForWorkViaWorkerFactory 767\nmain 1\nmain;work 2\n"
    );
}

[Test]
sample_reports_fold_their_call_trees() {
    expect_equal(
        folded("sample.txt"),
        "start;main 1\nstart;main;_pep_malloc 3\nstart;main;work 2\nstart;main;work;Array<int>.count 4\n"
    );
}

[Test]
an_unreadable_recording_is_an_error() {
    var folder = TempFolder("pep_profile_bad");
    var notes = folder.path.join("notes.txt");
    write_file(notes, "just some words\n");
    var output = run(pep_profile(["-i", notes.to_string(), "-o", folder.path.join("x.svg").to_string()]));
    expect_exit(output, 1);
    expect_contains(output.stderr, "is not a recording pep-profile can read");
    # Nothing to profile is a usage error.
    expect_exit(run(pep_profile(Array<String>())), 2);
}

# A profiler that can record this machine: samply, or a perf that runs
# (in a container, perf events are often not allowed).
working_profiler(): String? {
    if (works(process.Command("samply").argument("--version"))) {
        return Optional<String>.Value("samply");
    }
    var linux = os.system_os() == os.OperatingSystem.Linux;
    if (linux and works(process.Command("perf").arguments(["record", "-o", "/dev/null", "--", "true"]))) {
        return Optional<String>.Value("perf");
    }
    return Optional<String>.Empty;
}

# Whether `command` starts and succeeds.
works(command: process.Command): bool {
    var ran = command.run();
    return ran.is_ok() and ran.value().status.success();
}

[Test]
a_program_profiles_end_to_end_when_a_profiler_is_installed() {
    var profiler = working_profiler();
    if (profiler.is_empty()) {
        print("skipped: no samply, and no perf that can record here");
        return;
    }
    var folder = TempFolder("pep_profile_live");
    # Built as pep-profile builds a `.pep` file.
    var program = folder.path.join("spin" + toolchain.executable_suffix());
    var error = build_program(
        recording("spin.pep"), program, folder.path.join("build"), ["-O2", "-g", "--frame-pointers"]
    );
    if (error.is_value()) {
        panic($"spin.pep does not build:\n{error.value()}");
    }
    var stacks = folder.path.join("spin.folded");
    var output = run(
        pep_profile(
            ["--profiler", profiler.value(), "--folded", stacks.to_string()]
        ).arguments(["-o", folder.path.join("spin.svg").to_string(), program.to_string()])
    );
    # On Windows, samply records only from an Administrator terminal.
    var refused = output.stderr.contains("did not record a profile")
        or output.stderr.contains("needs administrator rights");
    if (!output.status.success() and refused) {
        print($"skipped: {profiler.value()} cannot record here:\n{output.stderr}");
        return;
    }
    expect_exit(output, 0);
    # `spin` is inlined into `main`; the debug info, when a symbolizer
    # reads it, names it as well.
    expect_contains(read_file(stacks), "main");
}
