# The platform's log on a phone (runtime/mobile.pep). On Android, what a
# panic writes reaches logcat; scripts/mobile-test.sh checks the rest
# (a real panic, standard output and error at /dev/null, and iOS's unified
# log, which a program in the simulator cannot read).

import os;
import process;

[Test]
[Target(OS(Android))]
what_a_panic_writes_reaches_logcat() {
    var marker = $"pepper-mobile-test-{os.SystemTime.now().unix_milliseconds()}";
    _pep_write_error($"{marker} first\n{marker} second\n".c_str());
    var log = process.Command("logcat").arguments(["-d", "-e", marker]).run();
    expect_true(log.is_ok());
    expect_true(log.value().stdout.contains($"{marker} first"));
    expect_true(log.value().stdout.contains($"{marker} second"));
}

[Test]
[Target(OS(IOS) || OS(Android))]
an_attached_standard_output_stays_where_it_is() {
    # pep-test reads the test program's output through a pipe.
    expect_false(_pep_platform_log_routes(1));
}
