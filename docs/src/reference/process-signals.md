<!-- Generated from runtime/process/signals.pep by `pep-doc reference`. Do not edit. -->

# Signals

Signals: Ctrl-C, a request to terminate and a hangup, received as values
on a `Channel` so a program can shut down cleanly.

`signals()` returns a channel that receives each signal it names. No
program code runs inside an operating-system signal handler: on POSIX the
handler only writes a byte to a pipe, and a runtime thread turns that byte
into a channel message; on Windows the console control handler already
runs on a thread of its own and sends the message itself.

Source: `runtime/process/signals.pep`

## Signal

```pepper
enum Signal
```

A signal a program can receive from `signals()`.

### Cases

#### Interrupt

```pepper
Interrupt
```

Ctrl-C: POSIX `SIGINT`, or Windows `CTRL_C_EVENT` and
`CTRL_BREAK_EVENT`.

#### Terminate

```pepper
Terminate
```

A request to end: POSIX `SIGTERM`, or Windows `CTRL_CLOSE_EVENT`,
`CTRL_LOGOFF_EVENT` and `CTRL_SHUTDOWN_EVENT`.

#### Hangup

```pepper
Hangup
```

The terminal closed: POSIX `SIGHUP`. Windows never sends it.

## signals

```pepper
signals(wanted: Array<Signal>): async.Channel<Signal>
```

Returns a new channel that receives each of `wanted` when the process
gets it, instead of the signal's default action (ending the program).

Receive from it like any channel: `receive()` waits outside a task and
suspends inside one, and a task can `select` on it. Every channel that
names a signal receives it. Closing the channel stops it receiving (the
runtime lets go of it at the next signal or `signals()` call); once no
open channel names a signal, the signal's default action returns.

Nothing runs inside an operating-system signal handler, so the program
reacts to a signal only by receiving from the channel. On Windows, the
system ends the program a few seconds after `Terminate` (the console
closing, a log-off or a shutdown) whatever it does, so clean up quickly.
WASI has no signals: the channel never receives.

**Parameters**
- `wanted` — the signals the channel receives

**Returns**
- the channel

**Example**
```pepper
import process;
import [Signal] from process;

main(): int {
    var stop = process.signals([Signal.Interrupt, Signal.Terminate]);
    start_serving();
    stop.receive();
    print("shutting down");
    stop_serving();
    return 0;
}
```
