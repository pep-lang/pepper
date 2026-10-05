<!-- Generated from runtime/async/select.pep by `pep-doc reference`. Do not edit. -->

# Select

Waiting on several channels at once: `Select<E>` takes the first value
any of them receives, or sends a value to the first that has room, and
turns what happened into a case of your own enum, which a `match` then
handles.

Source: `runtime/async/select.pep`

## Select

```pepper
struct Select<E>
```

Waits on several channels at once and takes the first value any of them
receives, or sends to the first that has room, like Go's `select`.

Each channel to receive from is added with `receive(channel, wrap)`,
where `wrap` turns one of its values into an `E`, usually a case of an
enum of your own that carries it. A value to send is added with
`send(channel, value, sent)`, where `sent` returns the `E` that says it
was sent. `wait()` then fires whichever arm is ready first and returns
its `E`, for a `match` to handle. The channels may carry different types.

- The value is taken under the channel's own lock, so no other receiver
  can take it between "ready" and "take".
- A send arm's value goes into its channel only when that arm fires;
  until then the select holds it. Once sent, the arm leaves the select,
  so the next `wait()` does not send it again. A value never sent is
  dropped with the select.
- When several channels have values, each wait starts after the channel
  that fired last, so a busy channel cannot starve the others.
- A channel that is closed and empty is skipped, and so is a send arm
  whose channel is closed. Once every arm is, `wait()` returns an error.
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

#### send

```pepper
send<T>(channel: Channel<T>, [Move] value: T, sent: () => E)
```

Adds a send arm: `wait()` sends `value` to `channel` once the channel
has room (a bounded channel that is full waits), and returns what
`sent` returns.

`value` must be a new value, as for `Channel.send`: the select holds
it and moves it into the channel only when this arm fires, so it is
never sent if another arm fires first. Once sent, the arm leaves the
select. A send arm whose channel is closed never fires, and its value
is dropped with the select.

**Type parameters**
- `T` — the type of the channel's values

**Parameters**
- `channel` — the channel to send to
- `value` — the value to send; a new value, which the compiler checks
- `sent` — returns the `E` that `wait()` returns once the value is sent; it runs on the waiting thread

**Example**
```pepper
select.send(results, copy(line), (): Event => Event.Sent);
```

#### wait

```pepper
wait(): Result<E>
```

Fires the first arm that is ready, waiting until one is: takes the
next value any of the channels receives, or sends a send arm's value
to a channel with room.

**Returns**
- the arm's `E` (the value received, turned into an `E`, or what a send arm's `sent` returned); or an error once every channel is closed (and empty, for a receive arm), when the select has no arms, or when the task's wait was cancelled or timed out

#### wait_for

```pepper
wait_for(milliseconds: ulong): Result<E>
```

Like `wait()`, but gives up after about `milliseconds` milliseconds.

**Parameters**
- `milliseconds` — the longest time to wait

**Returns**
- the arm's `E`, as for `wait()`; or an error if the time ran out, once every channel is closed (and empty, for a receive arm), or when the task's wait was cancelled

#### try_wait

```pepper
try_wait(): Result<E>
```

Fires an arm if one is ready now, without waiting: takes a value if a
channel has one waiting, or sends a send arm's value if its channel
has room.

**Returns**
- the arm's `E`, as for `wait()`; or an error if no arm is ready, or once every channel is closed (and empty, for a receive arm)
