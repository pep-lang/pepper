<!-- Generated from runtime/async/driver.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# I/O backends

I/O backends: how a task runtime waits for sockets.

Source: `runtime/async/driver.pep`

## Backend

```pepper
enum Backend
```

The I/O backend a runtime waits on sockets with (see
`RuntimeOptions.backend`).

### Cases

#### Automatic

```pepper
Automatic
```

The best one the system has: epoll on Linux, kqueue on macOS, IOCP on
Windows. The `PEPPER_IO_BACKEND` environment variable (`epoll`,
`kqueue`, `iocp` or `poll`) picks another.

#### Epoll

```pepper
Epoll
```

Linux's epoll, edge-triggered.

#### Kqueue

```pepper
Kqueue
```

The BSD and macOS kqueue, edge-triggered.

#### Iocp

```pepper
Iocp
```

A Windows I/O completion port, fed readiness by AFD poll requests.

#### Poll

```pepper
Poll
```

`poll()` (`WSAPoll` on Windows): available everywhere, but each wait
passes every waiting socket to the system, so it suits few
connections. The reference the others are tested against.
