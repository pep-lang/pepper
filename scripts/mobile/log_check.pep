# Writes to the platform's log on a phone, for scripts/mobile-test.sh:
#
#   log_check <marker> [panic]
#
# Prints `<marker> stdout` on standard output and `<marker> stderr` on
# standard error, which reach logcat or the unified log when they are
# /dev/null, as in an app. With `panic`, then panics with `<marker> panic`,
# which reaches the log either way.

import io;

main(args: String[]): int {
    var marker = args.count > 1 ? args[1] : "pepper-log-check";
    print($"{marker} stdout");
    io.File.stderr().write_all($"{marker} stderr\n".bytes());
    if (args.count > 2 && args[2] == "panic") {
        panic($"{marker} panic");
    }
    return 0;
}
