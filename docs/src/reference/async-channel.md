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

`T` must be thread-safe (a number, a `[Shared]` struct, a `shared` function
type such as `ThreadBody`), and is passed by reference; `Channel<String>` is
a compile error.

A Channel is `[Shared]`: keep it in a module-scope variable or pass it to
threads.

**Type parameters**
- `T` — the type of the values carried, which must be thread-safe

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

### Fields

#### Capacity

```pepper
const Capacity: ulong
```

The most values that may wait before `send` blocks, or 0 for no limit.

#### Lock

```pepper
const Lock: __ptr<void>
```

The platform mutex that guards `State` and `Buffer`.

#### NotEmpty

```pepper
const NotEmpty: __ptr<void>
```

The platform condition variable receivers wait on.

#### NotFull

```pepper
const NotFull: __ptr<void>
```

The platform condition variable senders wait on while a bounded
channel is full.

#### State

```pepper
const State: __ptr<ulong>
```

The head index, the number of queued values, the number of slots in
the buffer, and 1 once closed. Read and written only under `Lock`.

#### Buffer

```pepper
const Buffer: __ptr<__ptr<T>>
```

Holds the ring buffer of values. Read and written only under `Lock`.

### Constructor

#### Channel()

```pepper
construct(ulong capacity = 0)
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
bool send(T value)
```

Queues `value`, first waiting while a bounded channel is full.

**Parameters**
- `value` — the value to send

**Returns**
- true if the value was queued, false if the channel is closed (the value is dropped)

**Example**
```pepper
    if (!results.send(42)) {
        print("nobody is listening any more\n");
    }
```

#### try_send

```pepper
bool try_send(T value)
```

Queues `value` only if there is room right now, without waiting.

**Parameters**
- `value` — the value to send

**Returns**
- true if the value was queued, false if the channel is full or closed

#### receive

```pepper
Result<T> receive()
```

Takes the next value, waiting until one arrives.

**Returns**
- the value, or an error once the channel is closed and empty

**Example**
```pepper
    var job = jobs.receive();
    if (job.is_ok()) {
        run(job.value());
    }
```

#### try_receive

```pepper
Result<T> try_receive()
```

Takes the next value if one is waiting, without waiting.

**Returns**
- the value, or an error if none is waiting (see `is_closed()` to tell an empty channel from a closed one)

#### receive_for

```pepper
Result<T> receive_for(ulong milliseconds)
```

Like `receive()`, but gives up after about `milliseconds` milliseconds.

**Parameters**
- `milliseconds` — the longest time to wait

**Returns**
- the value, or an error if the time ran out or once the channel is closed and empty

#### close

```pepper
void close()
```

Closes the channel and wakes every waiting sender and receiver.

Later sends fail. Values already queued stay, and receivers still get
them; after the last one, `receive()` returns an error and `for` loops
end. Closing a closed channel does nothing.

#### is_closed

```pepper
bool is_closed()
```

Reports whether `close()` has been called.

**Returns**
- true once the channel is closed, even while values are still queued

#### count

```pepper
ulong count()
```

Returns the number of values waiting to be received. Other threads may
change it as soon as it returns.

**Returns**
- the number of queued values

#### iterate

```pepper
ChannelIterator<T> iterate()
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

### Fields

#### Source

```pepper
const Source: Channel<T>
```

The channel it receives from.

#### Current

```pepper
T Current
```

The value the last successful `next()` received.

### Constructor

#### ChannelIterator()

```pepper
construct(Channel<T> source)
```

Creates an iterator that receives from `source`. `source.iterate()`
does the same.

**Parameters**
- `source` — the channel to receive from

### Methods

#### next

```pepper
bool next()
```

Waits for the next value.

**Returns**
- true if a value arrived (read it with `current()`), false once the channel is closed and empty

#### current

```pepper
T current()
```

Returns the value the last successful `next()` received.

**Returns**
- the current value
