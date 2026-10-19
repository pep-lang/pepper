# process.signals: a signal the process gets arrives on every open channel
# that names it, and not on one that does not.

import async;
import process;
import [Signal] from process;
import "../signals";

# Sends the process `which` the way the system would, and waits until the
# runtime's watcher thread is done with it: it frees what it used after the
# channels have the signal, and the leak check would count that otherwise.
[Target(OS(Linux) || OS(Mac))]
send(which: Signal) {
    var handled = _process_signals_handled.load();
    raise(_process_signal_number(which));
    while (_process_signals_handled.load() == handled) {
        async.Thread.sleep(1);
    }
}

# Windows has no way to send Ctrl-C to only this process, so call the
# console control handler as the system would. Its `Terminate` waits for
# the program to end, and it has no `Hangup`: only `Interrupt` is sent.
[Target(OS(Windows))]
send(which: Signal) {
    expect_true(which == Signal.Interrupt);
    expect_equal(_process_signal_console_handler(0), 1);
}

# The first signal starts what turns signals into messages, which stays
# for the program: a test starts it before it counts allocations.
[Target(!OS(Wasi))]
start(which: Signal) {
    keep_for_the_program(() => {
        var first_use = process.signals([which]);
        send(which);
        first_use.receive_for(10000);
        first_use.close();
        process.signals(Array<Signal>());
    });
}

# WASI has no signals.
[Target(!OS(Wasi))]
[Test]
an_interrupt_arrives_on_every_channel_that_names_it() {
    start(Signal.Interrupt);
    var first = process.signals([Signal.Interrupt]);
    var second = process.signals([Signal.Terminate, Signal.Interrupt]);
    var other = process.signals([Signal.Terminate]);
    send(Signal.Interrupt);
    expect_true(first.receive_for(10000).value() == Signal.Interrupt);
    expect_true(second.receive_for(10000).value() == Signal.Interrupt);
    expect_true(other.try_receive().is_err());
    first.close();
    second.close();
    other.close();
    # Lets go of the closed channels.
    process.signals(Array<Signal>());
}

# Windows' `Terminate` waits for the program to end and it has no `Hangup`.
# (The test stays declared everywhere: a `[Test]` left out by `[Target]`
# is still listed in the test program.)
[Test]
terminate_and_hangup_arrive_on_the_channels_that_name_them() {
    [Target(OS(Linux) || OS(Mac))]
    {
        start(Signal.Terminate);
        start(Signal.Hangup);
        var terminate = process.signals([Signal.Terminate]);
        var hangup = process.signals([Signal.Hangup]);
        var both = process.signals([Signal.Hangup, Signal.Terminate]);
        send(Signal.Terminate);
        expect_true(terminate.receive_for(10000).value() == Signal.Terminate);
        expect_true(both.receive_for(10000).value() == Signal.Terminate);
        expect_true(hangup.try_receive().is_err());
        send(Signal.Hangup);
        expect_true(hangup.receive_for(10000).value() == Signal.Hangup);
        expect_true(both.receive_for(10000).value() == Signal.Hangup);
        expect_true(terminate.try_receive().is_err());
        terminate.close();
        hangup.close();
        both.close();
        process.signals(Array<Signal>());
    }
}

# Subscribing, getting a signal and closing, over and over, leaves nothing
# behind and frees nothing twice (#1006).
[Target(!OS(Wasi))]
[Test]
closes_and_subscribes_again_100_times() {
    start(Signal.Interrupt);
    for (var i in 0..100) {
        var channel = process.signals([Signal.Interrupt]);
        send(Signal.Interrupt);
        expect_true(channel.receive_for(10000).value() == Signal.Interrupt);
        channel.close();
        process.signals(Array<Signal>());
    }
}
