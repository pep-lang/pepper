# Starts copies of itself as children, its first argument saying what the
# child does, so it needs no other program on any platform
# (programs_test.pep).

import async;
import io;
import process;

extern char* getenv(char* name);

# The child side: what the parent asked for in `args[1]`.
child(args: String[]): int {
    var mode = args[1];
    if (mode == "arguments") {
        var index = 2;
        while (index < args.count) {
            print("[" + args[index] + "]");
            index = index + 1;
        }
        return 0;
    }
    if (mode == "streams") {
        io.File.stdout().write_all("out");
        io.File.stderr().write_all("err");
        return 3;
    }
    if (mode == "environment") {
        var name = "PROCESS_TEST_VALUE";
        var value = getenv(name.c_str());
        print(value == __null ? "<unset>" : String(value));
        var home = "PROCESS_TEST_KEEP";
        print(getenv(home.c_str()) == __null ? "<unset>" : "kept");
        return 0;
    }
    if (mode == "upper") {
        var text = io.File.stdin().read_string().value();
        io.File.stdout().write_all(text.upper());
        return 0;
    }
    if (mode == "directory") {
        print(process.working_directory().value().file_name().value());
        return 0;
    }
    if (mode == "sleep") {
        async.Thread.sleep(30000);
        return 0;
    }
    if (mode == "big") {
        # More than a pipe holds, on both streams.
        var line = "0123456789012345678901234567890123456789012345678901234567890123\n";
        var index = 0;
        while (index < 4096) {
            io.File.stdout().write_all(line);
            io.File.stderr().write_all(line);
            index = index + 1;
        }
        return 0;
    }
    return 100;
}

# A child's output with Windows line endings as `\n`: `print` writes `\n`
# as `\r\n` there, so printing the child's text again would double them.
lines(text: String): String {
    return text.replace("\r\n", "\n");
}

main(args: String[]): int {
    if (args.count > 1) {
        return child(args);
    }
    var self = process.executable_path().value().to_string();
    print(process.executable_path().value().file_name().value().contains("process_command") ? "path ok" : "path wrong");

    var arguments = process
        .Command(self)
        .arguments(["arguments", "two words", "", "quote\"d", "back\\slash\\", "tab\there"])
        .run()
        .value();
    print(lines(arguments.stdout));

    var streams = process.Command(self).argument("streams").run().value();
    print($"{streams.stdout}|{streams.stderr}|{streams.status.code().value()}|{streams.status.success()}");

    var environment = process
        .Command(self)
        .argument("environment")
        .environment("PROCESS_TEST_VALUE", "set")
        .environment("PROCESS_TEST_KEEP", "1")
        .remove_environment("PROCESS_TEST_KEEP")
        .run()
        .value();
    print(lines(environment.stdout));

    var upper = process
        .Command(self)
        .argument("upper")
        .stdin(process.Stream.Pipe)
        .stdout(process.Stream.Pipe)
        .spawn()
        .value();
    upper.stdin().write_all("pear and apple");
    upper.stdin().close();
    print(lines(upper.stdout().read_string().value()));
    print($"{upper.wait().value().success()}");

    var directory = io.Directory.temp().join("process_command_directory");
    io.Directory.create_all(directory);
    var moved = process.Command(self).argument("directory").working_directory(directory).run().value();
    print(lines(moved.stdout));

    var sleeper = process.Command(self).argument("sleep").spawn().value();
    print($"{sleeper.try_wait().value().is_empty()}");
    sleeper.kill();
    var killed = sleeper.wait().value();
    print($"killed {killed.success()}");

    var silent = process
        .Command(self)
        .argument("streams")
        .stdout(process.Stream.Null)
        .stderr(process.Stream.Null)
        .run()
        .value();
    print($"null {silent.stdout.size} {silent.stderr.size}");

    async.run(() => {
        var tasks = Array<async.Task<int>>();
        var index = 0;
        while (index < 3) {
            tasks.append(async.spawn<int>(() => {
                var me = process.executable_path().value().to_string();
                var big = process.Command(me).argument("big").run().value();
                return (big.stdout.size + big.stderr.size) as int;
            }));
            index = index + 1;
        }
        for (var task in tasks) {
            print($"task {task.join().value()}");
        }
    });
    return 0;
}
