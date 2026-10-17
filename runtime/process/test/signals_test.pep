# process.signals: a signal the process gets arrives on every open channel
# that names it, and not on one that does not.

import process;
import [Signal] from process;
import "../signals";

# Sends the process Ctrl-C the way the system would.
[Target(OS(Linux) || OS(Mac))]
interrupt() {
    raise(2);  # SIGINT
}

# Windows has no way to send Ctrl-C to only this process, so call the
# console control handler as the system would.
[Target(OS(Windows))]
interrupt() {
    expect_equal(_process_signal_console_handler(0), 1);
}

# WASI has no signals.
[Target(!OS(Wasi))]
[Test]
an_interrupt_arrives_on_every_channel_that_names_it() {
    # The first signal starts what turns signals into messages, which stays.
    keep_for_the_program(() => {
        var first_use = process.signals([Signal.Interrupt]);
        interrupt();
        first_use.receive_for(10000);
        first_use.close();
        process.signals(Array<Signal>());
    });
    var first = process.signals([Signal.Interrupt]);
    var second = process.signals([Signal.Terminate, Signal.Interrupt]);
    var other = process.signals([Signal.Terminate]);
    interrupt();
    expect_true(first.receive_for(10000).value() == Signal.Interrupt);
    expect_true(second.receive_for(10000).value() == Signal.Interrupt);
    expect_true(other.try_receive().is_err());
    first.close();
    second.close();
    other.close();
    # Lets go of the closed channels.
    process.signals(Array<Signal>());
}
