## Signals: Ctrl-C, a request to terminate and a hangup, received as values
## on a `Channel` so a program can shut down cleanly.
##
## `signals()` returns a channel that receives each signal it names. No
## program code runs inside an operating-system signal handler: on POSIX the
## handler only writes a byte to a pipe, and a runtime thread turns that byte
## into a channel message; on Windows the console control handler already
## runs on a thread of its own and sends the message itself.

# A signal's way in, on POSIX: the handler writes the signal's number to a
# non-blocking pipe (async-signal-safe; a full pipe drops the byte rather
# than block), and `_process_signal_watch` reads it on its own thread and
# sends it to every open channel subscribed to it. When none is open, the
# watcher restores the default action and raises the signal again, so a
# program that has closed its channels ends as if it never asked.

import async;
import "sys_posix";
import "sys_windows";

## A signal a program can receive from `signals()`.
export enum Signal {
    ## Ctrl-C: POSIX `SIGINT`, or Windows `CTRL_C_EVENT` and
    ## `CTRL_BREAK_EVENT`.
    Interrupt,
    ## A request to end: POSIX `SIGTERM`, or Windows `CTRL_CLOSE_EVENT`,
    ## `CTRL_LOGOFF_EVENT` and `CTRL_SHUTDOWN_EVENT`.
    Terminate,
    ## The terminal closed: POSIX `SIGHUP`. Windows never sends it.
    Hangup,
}

# One channel's interest in one signal.
struct _SignalSubscription {
    const signal: Signal;
    const channel: async.Channel<Signal>;

    construct(signal: Signal, channel: async.Channel<Signal>) {
        this.signal = signal;
        this.channel = channel;
    }
}

# Every channel's subscriptions, in a struct so that dropping the closed ones
# can replace the Array and free its storage.
struct _SignalSubscriptions {
    var list = Array<_SignalSubscription>();
}

const _process_signal_subscriptions = async.Mutex<_SignalSubscriptions>(_SignalSubscriptions());
const _process_signal_start = async.Once();

## Returns a new channel that receives each of `wanted` when the process
## gets it, instead of the signal's default action (ending the program).
##
## Receive from it like any channel: `receive()` waits outside a task and
## suspends inside one, and a task can `select` on it. Every channel that
## names a signal receives it. Closing the channel stops it receiving (the
## runtime lets go of it at the next signal or `signals()` call); once no
## open channel names a signal, the signal's default action returns.
##
## Nothing runs inside an operating-system signal handler, so the program
## reacts to a signal only by receiving from the channel. On Windows, the
## system ends the program a few seconds after `Terminate` (the console
## closing, a log-off or a shutdown) whatever it does, so clean up quickly.
## WASI has no signals: the channel never receives.
##
## @param wanted the signals the channel receives
## @returns the channel
## @example
##     import process;
##     import [Signal] from process;
##
##     main(): int {
##         var stop = process.signals([Signal.Interrupt, Signal.Terminate]);
##         start_serving();
##         stop.receive();
##         print("shutting down");
##         stop_serving();
##         return 0;
##     }
export signals(wanted: Array<Signal>): async.Channel<Signal> {
    var channel = async.Channel<Signal>();
    with (var subscriptions = _process_signal_subscriptions.lock()) {
        _process_drop_closed_subscriptions(subscriptions);
        for (var which in wanted) {
            subscriptions.list.append(_SignalSubscription(which, channel));
        }
    }
    _process_signal_start.call(_process_sys_start_signals);
    for (var which in wanted) {
        _process_sys_handle_signal(which);
    }
    return channel;
}

# Sends `which` to every open channel subscribed to it. Returns whether any
# received it.
_process_deliver_signal(which: Signal): bool {
    var delivered = false;
    with (var subscriptions = _process_signal_subscriptions.lock()) {
        _process_drop_closed_subscriptions(subscriptions);
        for (var subscription in subscriptions.list) {
            if (subscription.signal == which) {
                delivered = subscription.channel.send(which) or delivered;
            }
        }
    }
    return delivered;
}

# Forgets the channels that were closed, so they can be freed.
_process_drop_closed_subscriptions(subscriptions: _SignalSubscriptions) {
    var open = Array<_SignalSubscription>();
    for (var subscription in subscriptions.list) {
        if (!subscription.channel.is_closed()) {
            open.append(subscription);
        }
    }
    subscriptions.list = open;
}

[Target(OS(Linux) || OS(Mac))]
extern void* signal(int number, void* handler);
[Target(OS(Linux) || OS(Mac))]
extern int raise(int number);

# The write end of the pipe the handler writes to, or -1 before
# `_process_sys_start_signals`.
[Target(OS(Linux) || OS(Mac))]
const _process_signal_write_end = async.Atomic<int>(-1);

# One byte per signal number, each holding its own number: what the handler
# writes, since it cannot allocate.
[Target(OS(Linux) || OS(Mac))]
const _process_signal_numbers: __ptr<u8> = _process_new_signal_numbers();

[Target(OS(Linux) || OS(Mac))]
_process_new_signal_numbers(): __ptr<u8> {
    __ptr<u8> numbers = _pep_malloc(32);
    for (var number in 0..32) {
        numbers[number] = number as u8;
    }
    return numbers;
}

[Target(OS(Linux) || OS(Mac))]
_process_signal_number(which: Signal): int {
    if (which == Signal.Interrupt) {
        return 2;  # SIGINT
    }
    if (which == Signal.Terminate) {
        return 15;  # SIGTERM
    }
    return 1;  # SIGHUP
}

[Target(OS(Linux) || OS(Mac))]
_process_sys_start_signals() {
    __ptr<int> ends = _pep_malloc(8);
    var made = _process_pipe(ends);
    var read_end = ends[0];
    var write_end = ends[1];
    _pep_free(ends);
    if (!made) {
        panic("process.signals: cannot make a pipe");
    }
    _process_set_nonblocking(write_end);
    _process_signal_write_end.store(write_end);
    async.Thread.spawn(() => _process_signal_watch(read_end));
}

[Target(OS(Linux))]
_process_set_nonblocking(descriptor: int) {
    fcntl(descriptor, 4, 2048);  # F_SETFL, O_NONBLOCK
}

[Target(OS(Mac))]
_process_set_nonblocking(descriptor: int) {
    fcntl(descriptor, 4, 4);  # F_SETFL, O_NONBLOCK
}

[Target(OS(Linux) || OS(Mac))]
_process_sys_handle_signal(which: Signal) {
    var handler: extern (int) => void = _process_signal_handler;
    signal(_process_signal_number(which), handler);
}

# The operating-system handler: async-signal context, so it only writes.
[Target(OS(Linux) || OS(Mac))]
_process_signal_handler(number: int) {
    var write_end = _process_signal_write_end.load();
    if (write_end < 0) {
        return;
    }
    write(write_end, _process_signal_numbers + number, 1);
}

[Target(OS(Linux) || OS(Mac))]
_process_signal_watch(read_end: int) {
    __ptr<u8> byte = _pep_malloc(1);
    while (true) {
        # The write end stays open, so a read only fails when interrupted.
        if (read(read_end, byte, 1) != 1) {
            continue;
        }
        var number = byte[0] as int;
        var which = number == 2 ? Signal.Interrupt : (number == 15 ? Signal.Terminate : Signal.Hangup);
        if (_process_deliver_signal(which)) {
            continue;
        }
        signal(number, __null);  # SIG_DFL
        raise(number);
    }
}

[Target(OS(Windows))]
extern void Sleep(uint milliseconds);

[Target(OS(Windows))]
_process_sys_start_signals() {
    var handler: extern (uint) => int = _process_signal_console_handler;
    SetConsoleCtrlHandler(handler, 1);
}

[Target(OS(Windows))]
_process_sys_handle_signal(which: Signal) {}

# Windows calls console control handlers on a new thread, not in signal
# context, so this one delivers the event itself. Returning 0 passes it on
# to the default handler, which ends the process.
[Target(OS(Windows))]
_process_signal_console_handler(event: uint): int {
    # CTRL_C_EVENT 0 and CTRL_BREAK_EVENT 1; CTRL_CLOSE_EVENT 2,
    # CTRL_LOGOFF_EVENT 5 and CTRL_SHUTDOWN_EVENT 6.
    var which = event <= 1 ? Signal.Interrupt : Signal.Terminate;
    if (!_process_deliver_signal(which)) {
        return 0;
    }
    if (which == Signal.Terminate) {
        # The process ends as soon as this returns: wait for the program
        # to finish instead, until the system's timeout ends it.
        Sleep(4294967295);  # INFINITE
    }
    return 1;
}

[Target(OS(Wasi))]
_process_sys_start_signals() {}

[Target(OS(Wasi))]
_process_sys_handle_signal(which: Signal) {}
