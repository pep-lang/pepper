<!-- Generated from runtime/async/channel.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# async/channel.pep

Channels: `Channel<T>` carries values from threads that send to threads
that receive, and `ChannelIterator<T>` receives in a `for` loop.

Source: `runtime/async/channel.pep`

## Channel

```pepper
[Shared] struct Channel<T>
```

A queue that carries values from threads that send to threads that
receive, like Go channels or Rust's `mpsc`, with any number of each.

Values arrive in the order they were sent (from any one sender). A
bounded channel holds at most `capacity` values, and `send` waits while it
is full; `Channel<T>(0)`, the default, is unbounded and `send` never waits.

`close()` ends the stream: later sends fail, and receivers take what is
left and then get an error. Only `close()` closes a channel; dropping it
or the threads that use it does not. `for (var v in channel)` receives
until the channel is closed and empty.

`send` takes a new value, which nothing on the sending thread references,
and hands it to the receiver without copying it: a constructor call, a
literal, a call that returns a fresh value, `move(x)` (a variable that
holds the only reference) or `copy(x)` (a copy, when the sender keeps
using `x`). Sending a variable that something else still references is a
compile error. A thread-safe value (a number, a `[Shared]` struct, a
`shared` function value such as a `ThreadBody`) passes freely.

A Channel is `[Shared]`: keep it in a module-scope variable or pass it to
threads.

**Type parameters**
- `T` — the type of the values carried

**Example**
```pepper
    import async;

    const jobs = async.Channel<long>(64);
    const total = Atomic<long>(0);

    worker() {
        for (var job in jobs) {
            total.fetch_add(job);
        }
    }

    main(): int {
        var thread = async.Thread.spawn(worker);
        jobs.send(20);
        jobs.send(22);
        jobs.close();
        thread.join();
        assert(total.load() == 42, "the worker received both jobs");
        return 0;
    }
```

### Constructor

#### Channel()

```pepper
construct(capacity: ulong = 0)
```

Creates an open, empty channel.

**Parameters**
- `capacity` — how many values may wait before `send` blocks; 0 (the default) for no limit

**Panics**
- if the operating system cannot create a mutex or condition variable

**Example**
```pepper
    var bounded = async.Channel<long>(16);
    var unbounded = async.Channel<long>();
```

### Methods

#### send

```pepper
send([Move] value: T): bool
```

Queues `value`, first waiting while a bounded channel is full.

`value` must be a new value: nothing else may reference it. The caller
hands its reference over and the value itself is queued, with no copy.
Pass `move(x)` to send a variable's value, or `copy(x)` to keep using
`x`.

In a task (see `run`), waiting parks the task and its worker runs
other tasks; a cancel or the task's `timeout` ends the wait.

**Parameters**
- `value` — the value to send; a new value, which the compiler checks

**Returns**
- true if the value was queued, false if the channel is closed or the task's wait was cancelled or timed out (the value is dropped)

**Example**
```pepper
    var line = "hello";
    lines.send(copy(line));
    line.append(" again");   # the receiver still gets "hello"
    lines.send(move(line));   # line is null now
```

#### try_send

```pepper
try_send([Move] value: T): bool
```

Queues `value` only if there is room right now, without waiting. The
value is dropped when it is not queued.

**Parameters**
- `value` — the value to send; a new value, as for `send`

**Returns**
- true if the value was queued, false if the channel is full or closed

#### receive

```pepper
receive(): Result<T>
```

Takes the next value, waiting until one arrives.

In a task (see `run`), waiting parks the task and its worker runs
other tasks; a cancel or the task's `timeout` ends the wait.

**Returns**
- the value, or an error once the channel is closed and empty, or when the task's wait was cancelled or timed out

**Example**
```pepper
    var job = jobs.receive();
    if (job.is_ok()) {
        run(job.value());
    }
```

#### try_receive

```pepper
try_receive(): Result<T>
```

Takes the next value if one is waiting, without waiting.

**Returns**
- the value, or an error if none is waiting (see `is_closed()` to tell an empty channel from a closed one)

#### receive_for

```pepper
receive_for(milliseconds: ulong): Result<T>
```

Like `receive()`, but gives up after about `milliseconds` milliseconds.

**Parameters**
- `milliseconds` — the longest time to wait

**Returns**
- the value, or an error if the time ran out, once the channel is closed and empty, or when the task's wait was cancelled

#### close

```pepper
close()
```

Closes the channel and wakes every waiting sender and receiver.

Later sends fail. Values already queued stay, and receivers still get
them; after the last one, `receive()` returns an error and `for` loops
end. Closing a closed channel does nothing.

#### is_closed

```pepper
is_closed(): bool
```

Reports whether `close()` has been called.

**Returns**
- true once the channel is closed, even while values are still queued

#### count

```pepper
count(): ulong
```

Returns the number of values waiting to be received. Other threads may
change it as soon as it returns.

**Returns**
- the number of queued values

#### iterate

```pepper
iterate(): ChannelIterator<T>
```

Returns an iterator that receives until the channel is closed and
empty. A `for` loop over the channel calls it.

Several threads may loop over one channel at once; each value goes to
exactly one of them.

**Returns**
- the iterator a `for` loop drives

**Example**
```pepper
    for (var line in lines) {
        print(line, "\n");
    }   # ends once `lines` is closed and empty
```

## ChannelIterator

```pepper
struct ChannelIterator<T>
```

Receives from a `Channel<T>` in a `for` loop: `next()` waits for the next
value and returns false once the channel is closed and empty.

`Channel.iterate()` returns one; a `for` loop over a channel uses it
without naming it. It belongs to the thread that runs the loop.

**Type parameters**
- `T` — the type of the values carried

**Example**
```pepper
    var values = jobs.iterate();
    while (values.next()) {
        total = total + values.current();
    }
```

### Constructor

#### ChannelIterator()

```pepper
construct(source: Channel<T>)
```

Creates an iterator that receives from `source`. `source.iterate()`
does the same.

**Parameters**
- `source` — the channel to receive from

### Methods

#### next

```pepper
next(): bool
```

Waits for the next value.

**Returns**
- true if a value arrived (read it with `current()`), false once the channel is closed and empty

#### current

```pepper
current(): T
```

Returns the value the last successful `next()` received.

**Returns**
- the current value
