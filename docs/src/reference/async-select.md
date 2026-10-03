<!-- Generated from runtime/async/select.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Select

Waiting on several channels at once: `Select<E>` takes the first value
any of them receives and turns it into a case of your own enum, which a
`match` then handles.

Source: `runtime/async/select.pep`

## Select

```pepper
struct Select<E>
```

Waits on several channels at once and takes the first value any of them
receives, like Go's `select`.

Each channel is added with `receive(channel, wrap)`, where `wrap` turns
one of its values into an `E`, usually a case of an enum of your own that
carries it. `wait()` then returns the next value from whichever channel
has one, as an `E`, for a `match` to handle. The channels may carry
different types.

- The value is taken under the channel's own lock, so no other receiver
  can take it between "ready" and "take".
- When several channels have values, each wait starts after the channel
  that fired last, so a busy channel cannot starve the others.
- A channel that is closed and empty is skipped. Once every channel is,
  `wait()` returns an error.
- In a task (see `run`), waiting parks the task and its worker runs other
  tasks; a cancel or the task's `timeout` ends the wait.

A Select is not `[Shared]`: use it from the thread (or task) that made it.

**Type parameters**
- `E` — the type every channel's values are turned into

**Example**
```pepper
    enum Event {
        Job(job: Job),
        Tick(count: long),
        Stop,
    }

    var select = async.Select<Event>();
    select.receive(jobs, (job: Job): Event => Event.Job(job));
    select.receive(ticks, (count: long): Event => Event.Tick(count));
    select.receive(quit, (stop: bool): Event => Event.Stop);
    var running = true;
    while (running) {
        match (select.wait()) {
            Ok(event) => {
                match (event) {
                    Job(job) => { run(job); }
                    Tick(count) => { report(count); }
                    Stop => { running = false; }
                }
            }
            Err(error) => { running = false; }   # every channel closed
        }
    }
```

### Constructor

#### Select()

```pepper
construct()
```

Creates a select with no channels yet.

### Methods

#### receive

```pepper
receive<T>(channel: Channel<T>, wrap: (T) => E)
```

Adds `channel`: its values, turned into an `E` by `wrap`, are among
those `wait()` returns.

**Type parameters**
- `T` — the type of the channel's values

**Parameters**
- `channel` — the channel to receive from
- `wrap` — turns a value received from `channel` into an `E`; it runs on the waiting thread

**Example**
```pepper
    select.receive(lines, (line: String): Event => Event.Line(line));
```

#### wait

```pepper
wait(): Result<E>
```

Takes the next value any of the channels receives, waiting until one
arrives.

**Returns**
- the value, turned into an `E`; or an error once every channel is closed and empty, when the select has no channels, or when the task's wait was cancelled or timed out

#### wait_for

```pepper
wait_for(milliseconds: ulong): Result<E>
```

Like `wait()`, but gives up after about `milliseconds` milliseconds.

**Parameters**
- `milliseconds` — the longest time to wait

**Returns**
- the value, turned into an `E`; or an error if the time ran out, once every channel is closed and empty, or when the task's wait was cancelled

#### try_wait

```pepper
try_wait(): Result<E>
```

Takes a value if any channel has one waiting, without waiting.

**Returns**
- the value, turned into an `E`; or an error if none is waiting, or once every channel is closed and empty
