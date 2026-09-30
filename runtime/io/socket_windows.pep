# Windows socket layer for io (Winsock 2, ws2_32). Every declaration carries
# [Target(OS(Windows))]; socket_posix.pep declares the same `_io_sys_*`
# socket functions with the same signatures for Linux and macOS.
#
# Winsock is started once per process with WSAStartup before the first
# socket or lookup, and never cleaned up. Sockets are created overlapped
# (so the event loop can later drive them through I/O completion ports),
# non-blocking (a call that would block waits in `_io_socket_wait` and tries
# again), and not inherited by child processes. Errors come from WSAGetLastError, whose
# WSAE* codes FormatMessageW describes like any other system error.

import "address";
import "socket";
import "sys_windows";
import "types";
import "wait";

# ── C functions (ws2_32, kernel32) ───────────────────────────────────────────

[Target(OS(Windows))]
[Link("ws2_32")]
extern int WSAStartup(ushort version, void* data);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int WSAGetLastError();
[Target(OS(Windows))]
[Link("ws2_32")]
extern ulong WSASocketW(int family, int kind, int protocol, void* info, uint group, uint flags);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int closesocket(ulong s);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int bind(ulong s, void* address, int length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int listen(ulong s, int backlog);
[Target(OS(Windows))]
[Link("ws2_32")]
extern ulong accept(ulong s, void* address, int* length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int connect(ulong s, void* address, int length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int recv(ulong s, void* buffer, int length, int flags);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int send(ulong s, void* buffer, int length, int flags);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int recvfrom(ulong s, void* buffer, int length, int flags, void* address, int* address_length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int sendto(ulong s, void* buffer, int length, int flags, void* address, int address_length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int shutdown(ulong s, int how);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int setsockopt(ulong s, int level, int name, void* value, int length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int getsockname(ulong s, void* address, int* length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int getpeername(ulong s, void* address, int* length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int GetAddrInfoW(ushort* node, ushort* service, void* hints, void* result);
[Target(OS(Windows))]
[Link("ws2_32")]
extern void FreeAddrInfoW(void* list);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int ioctlsocket(ulong s, int command, uint* argument);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int getsockopt(ulong s, int level, int name, void* value, int* length);
[Target(OS(Windows))]
[Link("ws2_32")]
extern int WSAPoll(void* descriptors, uint count, int timeout);
[Target(OS(Windows))]
extern int SetHandleInformation(ulong h, uint mask, uint flags);  # the SOCKET as a HANDLE

# ── Startup ──────────────────────────────────────────────────────────────────

# Set once Winsock is started. Two threads may both call WSAStartup the first
# time; it counts calls, so the extra one is harmless.
[Target(OS(Windows))]
const _io_winsock_started = Atomic<int>(0);

[Target(OS(Windows))]
export _io_win_socket_startup() {
    if (_io_winsock_started.load() != 0) {
        return;
    }
    var data = _pep_malloc(1024);  # WSADATA (408 bytes on 64-bit)
    WSAStartup(514, data);         # version 2.2
    _pep_free(data);
    _io_winsock_started.store(1);
}

# ── Errors ───────────────────────────────────────────────────────────────────

[Target(OS(Windows))]
export _io_sys_is_connection_refused(code: ErrorCode): bool {
    return code == 10061;  # WSAECONNREFUSED
}

[Target(OS(Windows))]
export _io_sys_is_connection_reset(code: ErrorCode): bool {
    return code == 10054 || code == 10053;  # WSAECONNRESET, WSAECONNABORTED
}

[Target(OS(Windows))]
export _io_sys_is_address_in_use(code: ErrorCode): bool {
    return code == 10048;  # WSAEADDRINUSE
}

[Target(OS(Windows))]
export _io_sys_is_address_not_available(code: ErrorCode): bool {
    return code == 10049;  # WSAEADDRNOTAVAIL
}

[Target(OS(Windows))]
export _io_sys_is_timed_out(code: ErrorCode): bool {
    return code == 10060;  # WSAETIMEDOUT
}

[Target(OS(Windows))]
export _io_sys_code_timed_out(): ErrorCode { return 10060; }

# Code for a stream that ended before the bytes asked for: ERROR_HANDLE_EOF.
[Target(OS(Windows))]
export _io_sys_code_unexpected_end(): ErrorCode { return 38; }

# The calling thread's last Winsock error.
[Target(OS(Windows))]
export _io_win_socket_error(): IoError {
    var code = WSAGetLastError() as ErrorCode;
    return IoError(code, _io_sys_error_message(code));
}

# 0 -> Ok, SOCKET_ERROR (-1) -> the Winsock error.
[Target(OS(Windows))]
export _io_win_socket_check(rc: int): IoResult<void> {
    if (rc == 0) {
        return _io_ok_void();
    }
    return IoResult<void>.err(_io_win_socket_error());
}

# One send or receive moves at most this many bytes (the length is an int).
[Target(OS(Windows))]
export _io_win_max_socket_rw(n: ulong): int {
    if (n > 1073741824) {
        return 1073741824;  # 1 GiB, as File does
    }
    return n as int;
}

# ── Handles ──────────────────────────────────────────────────────────────────

[Target(OS(Windows))]
export _io_sys_socket_invalid(): SocketHandle {
    return ~(0 as ulong);  # INVALID_SOCKET
}

[Target(OS(Windows))]
export _io_sys_socket_valid(h: SocketHandle): bool {
    return h != _io_sys_socket_invalid();
}

[Target(OS(Windows))]
export _io_sys_socket_close(h: SocketHandle): IoResult<void> {
    _io_socket_forget(h);
    return _io_win_socket_check(closesocket(h));
}

# Blocks the thread until `h` is ready for `interest`, or reports an error
# (WSAPoll).
[Target(OS(Windows))]
export _io_sys_socket_poll(h: SocketHandle, interest: int): IoResult<void> {
    var descriptor = _pep_malloc(16) as __ptr<ulong>;
    var events = descriptor as __ptr<u16>;
    descriptor[0] = h;
    events[4] = 256;  # POLLRDNORM
    if (interest == _IO_WRITABLE) {
        events[4] = 16;  # POLLWRNORM
    }
    events[5] = 0;
    var rc = WSAPoll(descriptor, 1, -1);
    _pep_free(descriptor);
    if (rc < 0) {
        return IoResult<void>.err(_io_win_socket_error());
    }
    return _io_ok_void();
}

# ── sockaddr ─────────────────────────────────────────────────────────────────

# A 16-bit family at 0: AF_INET 2, AF_INET6 23.
[Target(OS(Windows))]
export _io_sys_sockaddr_header(buffer: __ptr<u8>, v6: bool, length: int) {
    var family = 2;
    if (v6) {
        family = 23;
    }
    (buffer as __ptr<u16>)[0] = family as u16;
}

# 4 for IPv4, 6 for IPv6, 0 for any other family.
[Target(OS(Windows))]
export _io_sys_sockaddr_family(buffer: __ptr<u8>): int {
    var family = (buffer as __ptr<u16>)[0] as int;
    if (family == 2) {
        return 4;
    }
    if (family == 23) {
        return 6;
    }
    return 0;
}

# ── Socket calls ─────────────────────────────────────────────────────────────

# A new overlapped, non-inheritable, non-blocking socket (SOCK_STREAM 1 or
# SOCK_DGRAM 2). Every socket is non-blocking: a call that would block waits
# in `_io_socket_wait` and tries again.
[Target(OS(Windows))]
export _io_sys_socket_open(v6: bool, stream: bool): IoResult<SocketHandle> {
    _io_win_socket_startup();
    var family = 2;
    if (v6) {
        family = 23;
    }
    var kind = 2;
    if (stream) {
        kind = 1;
    }
    var s = WSASocketW(family, kind, 0, __null, 0, 129);  # WSA_FLAG_OVERLAPPED | WSA_FLAG_NO_HANDLE_INHERIT
    if (!_io_sys_socket_valid(s)) {
        return IoResult<SocketHandle>.err(_io_win_socket_error());
    }
    _io_win_set_non_blocking(s);
    return IoResult<SocketHandle>.ok(s);
}

# FIONBIO: makes `s` non-blocking.
[Target(OS(Windows))]
export _io_win_set_non_blocking(s: SocketHandle) {
    var on = _pep_malloc(4) as __ptr<uint>;
    on[0] = 1;
    ioctlsocket(s, -2147195266, on);  # FIONBIO (0x8004667E)
    _pep_free(on);
}

# After a failed call: waits for `interest` when `e` says the call would
# block (WSAEWOULDBLOCK), and succeeds when the call should be tried again;
# otherwise fails with the error to return.
[Target(OS(Windows))]
export _io_win_retry(h: SocketHandle, e: IoError, interest: int): IoResult<void> {
    if (e.code == 10035) {  # WSAEWOULDBLOCK
        return _io_socket_wait(h, interest);
    }
    return IoResult<void>.err(e);
}

[Target(OS(Windows))]
export _io_win_set_int_option(s: SocketHandle, level: int, name: int, value: int): IoResult<void> {
    var slot = _pep_malloc(4) as __ptr<int>;
    slot[0] = value;
    var rc = setsockopt(s, level, name, slot, 4);
    var result = _io_win_socket_check(rc);
    _pep_free(slot);
    return result;
}

# SO_REUSEADDR on Windows lets another socket take over a bound port, which
# POSIX's does not; listeners go without it, as Rust's do.
[Target(OS(Windows))]
export _io_sys_socket_set_reuse_address(h: SocketHandle): IoResult<void> {
    return _io_ok_void();
}

[Target(OS(Windows))]
export _io_sys_socket_set_no_delay(h: SocketHandle, enabled: bool): IoResult<void> {
    var value = 0;
    if (enabled) {
        value = 1;
    }
    return _io_win_set_int_option(h, 6, 1, value);  # IPPROTO_TCP, TCP_NODELAY
}

[Target(OS(Windows))]
export _io_sys_socket_set_broadcast(h: SocketHandle, enabled: bool): IoResult<void> {
    var value = 0;
    if (enabled) {
        value = 1;
    }
    return _io_win_set_int_option(h, 65535, 32, value);  # SOL_SOCKET, SO_BROADCAST
}

[Target(OS(Windows))]
export _io_sys_socket_bind(h: SocketHandle, address: SocketAddress): IoResult<void> {
    var buffer = _pep_malloc(_io_sockaddr_capacity()) as __ptr<u8>;
    var length = _io_sockaddr_write(buffer, address);
    var result = _io_win_socket_check(bind(h, buffer, length));
    _pep_free(buffer);
    return result;
}

[Target(OS(Windows))]
export _io_sys_socket_listen(h: SocketHandle, backlog: int): IoResult<void> {
    return _io_win_socket_check(listen(h, backlog));
}

# A non-blocking connect fails with WSAEWOULDBLOCK; it has finished when the
# socket is writable (or reports an error), and SO_ERROR says how.
[Target(OS(Windows))]
export _io_sys_socket_connect(h: SocketHandle, address: SocketAddress): IoResult<void> {
    var buffer = _pep_malloc(_io_sockaddr_capacity()) as __ptr<u8>;
    var length = _io_sockaddr_write(buffer, address);
    var rc = connect(h, buffer, length);
    _pep_free(buffer);
    if (rc == 0) {
        return _io_ok_void();
    }
    var e = _io_win_socket_error();
    if (e.code != 10035) {  # WSAEWOULDBLOCK
        return IoResult<void>.err(e);
    }
    var waited = _io_socket_wait(h, _IO_WRITABLE);
    if (waited.is_err()) {
        return waited;
    }
    var slot = _pep_malloc(8) as __ptr<int>;
    var size = slot + 1;
    slot[0] = 0;
    size[0] = 4;
    var got = getsockopt(h, 65535, 4103, slot, size);  # SOL_SOCKET, SO_ERROR
    var code = slot[0];
    _pep_free(slot);
    if (got != 0) {
        return IoResult<void>.err(_io_win_socket_error());
    }
    if (code != 0) {
        return IoResult<void>.err(IoError(code as ErrorCode, _io_sys_error_message(code as ErrorCode)));
    }
    return _io_ok_void();
}

[Target(OS(Windows))]
export _io_sys_socket_accept(h: SocketHandle): IoResult<(SocketHandle, SocketAddress)> {
    var buffer = _pep_malloc(_io_sockaddr_capacity()) as __ptr<u8>;
    var length = _pep_malloc(4) as __ptr<int>;
    var s = _io_sys_socket_invalid();
    while (true) {
        length[0] = _io_sockaddr_capacity() as int;
        s = accept(h, buffer, length);
        if (_io_sys_socket_valid(s)) {
            break;
        }
        var retry = _io_win_retry(h, _io_win_socket_error(), _IO_READABLE);
        if (retry.is_err()) {
            _pep_free(buffer);
            _pep_free(length);
            return IoResult<(SocketHandle, SocketAddress)>.err(retry.error());
        }
    }
    SetHandleInformation(s, 1, 0);  # HANDLE_FLAG_INHERIT off
    _io_win_set_non_blocking(s);
    var peer = _io_sockaddr_read(buffer);
    _pep_free(buffer);
    _pep_free(length);
    return IoResult<(SocketHandle, SocketAddress)>.ok((s, peer));
}

[Target(OS(Windows))]
export _io_sys_socket_receive(h: SocketHandle, destination: __ptr<u8>, n: ulong): IoResult<ulong> {
    while (true) {
        var r = recv(h, destination, _io_win_max_socket_rw(n), 0);
        if (r >= 0) {
            return IoResult<ulong>.ok(r as ulong);
        }
        var retry = _io_win_retry(h, _io_win_socket_error(), _IO_READABLE);
        if (retry.is_err()) {
            return IoResult<ulong>.err(retry.error());
        }
    }
    return IoResult<ulong>.ok(0);
}

[Target(OS(Windows))]
export _io_sys_socket_send(h: SocketHandle, source: __ptr<u8>, n: ulong): IoResult<ulong> {
    while (true) {
        var r = send(h, source, _io_win_max_socket_rw(n), 0);
        if (r >= 0) {
            return IoResult<ulong>.ok(r as ulong);
        }
        var retry = _io_win_retry(h, _io_win_socket_error(), _IO_WRITABLE);
        if (retry.is_err()) {
            return IoResult<ulong>.err(retry.error());
        }
    }
    return IoResult<ulong>.ok(0);
}

[Target(OS(Windows))]
export _io_sys_socket_send_to(h: SocketHandle, source: __ptr<u8>, n: ulong, address: SocketAddress): IoResult<ulong> {
    var buffer = _pep_malloc(_io_sockaddr_capacity()) as __ptr<u8>;
    var length = _io_sockaddr_write(buffer, address);
    while (true) {
        var r = sendto(h, source, _io_win_max_socket_rw(n), 0, buffer, length);
        if (r >= 0) {
            _pep_free(buffer);
            return IoResult<ulong>.ok(r as ulong);
        }
        var retry = _io_win_retry(h, _io_win_socket_error(), _IO_WRITABLE);
        if (retry.is_err()) {
            _pep_free(buffer);
            return IoResult<ulong>.err(retry.error());
        }
    }
    return IoResult<ulong>.ok(0);
}

# A datagram longer than `n` is truncated to `n` bytes; Winsock reports that
# as WSAEMSGSIZE with the buffer filled, which counts as success here, as on
# POSIX.
[Target(OS(Windows))]
export _io_sys_socket_receive_from(
    h: SocketHandle, destination: __ptr<u8>, n: ulong
): IoResult<(ulong, SocketAddress)> {
    var buffer = _pep_malloc(_io_sockaddr_capacity()) as __ptr<u8>;
    var length = _pep_malloc(4) as __ptr<int>;
    length[0] = _io_sockaddr_capacity() as int;
    var limit = _io_win_max_socket_rw(n);
    var r = 0;
    while (true) {
        length[0] = _io_sockaddr_capacity() as int;
        r = recvfrom(h, destination, limit, 0, buffer, length);
        if (r >= 0) {
            break;
        }
        var e = _io_win_socket_error();
        if (e.code == 10040) {  # WSAEMSGSIZE
            r = limit;
            break;
        }
        var retry = _io_win_retry(h, e, _IO_READABLE);
        if (retry.is_err()) {
            _pep_free(buffer);
            _pep_free(length);
            return IoResult<(ulong, SocketAddress)>.err(retry.error());
        }
    }
    var from = _io_sockaddr_read(buffer);
    _pep_free(buffer);
    _pep_free(length);
    return IoResult<(ulong, SocketAddress)>.ok((r as ulong, from));
}

# how: 0 reading, 1 writing, 2 both (SD_RECEIVE, SD_SEND, SD_BOTH).
[Target(OS(Windows))]
export _io_sys_socket_shutdown(h: SocketHandle, how: int): IoResult<void> {
    return _io_win_socket_check(shutdown(h, how));
}

[Target(OS(Windows))]
export _io_sys_socket_local_address(h: SocketHandle): IoResult<SocketAddress> {
    var buffer = _pep_malloc(_io_sockaddr_capacity()) as __ptr<u8>;
    var length = _pep_malloc(4) as __ptr<int>;
    length[0] = _io_sockaddr_capacity() as int;
    var rc = getsockname(h, buffer, length);
    return _io_win_address_result(rc, buffer, length);
}

[Target(OS(Windows))]
export _io_sys_socket_peer_address(h: SocketHandle): IoResult<SocketAddress> {
    var buffer = _pep_malloc(_io_sockaddr_capacity()) as __ptr<u8>;
    var length = _pep_malloc(4) as __ptr<int>;
    length[0] = _io_sockaddr_capacity() as int;
    var rc = getpeername(h, buffer, length);
    return _io_win_address_result(rc, buffer, length);
}

# The address getsockname/getpeername wrote, or the Winsock error; frees both
# buffers.
[Target(OS(Windows))]
export _io_win_address_result(rc: int, buffer: __ptr<u8>, length: __ptr<int>): IoResult<SocketAddress> {
    if (rc != 0) {
        var e = _io_win_socket_error();
        _pep_free(buffer);
        _pep_free(length);
        return IoResult<SocketAddress>.err(e);
    }
    var address = _io_sockaddr_read(buffer);
    _pep_free(buffer);
    _pep_free(length);
    return IoResult<SocketAddress>.ok(address);
}

# ── Name resolution ──────────────────────────────────────────────────────────
# ADDRINFOW: ai_flags @0, ai_family @4, ai_socktype @8, ai_protocol @12,
# ai_addrlen (size_t) @16, ai_canonname @24, ai_addr @32, ai_next @40; 48
# bytes in all.

[Target(OS(Windows))]
export _io_sys_resolve(host: String, port: u16): IoResult<SocketAddress[]> {
    _io_win_socket_startup();
    var hints = _pep_malloc(48) as __ptr<int>;
    hints[2] = 1;  # ai_socktype = SOCK_STREAM: one entry per address
    var list = _pep_malloc(8) as __ptr<__ptr<u8>>;
    var node = _io_win_wide(host);
    var rc = GetAddrInfoW(node, __null, hints, list);
    _pep_free(node);
    _pep_free(hints);
    if (rc != 0) {
        _pep_free(list);
        var code = rc as ErrorCode;
        var message = "failed to resolve '" + host + "': " + _io_sys_error_message(code);
        if (code == 11001 || code == 11004) {  # WSAHOST_NOT_FOUND, WSANO_DATA
            return IoResult<SocketAddress[]>.err(IoError(_io_sys_code_not_found(), message));
        }
        return IoResult<SocketAddress[]>.err(IoError(code, message));
    }
    var out = Array<SocketAddress>();
    var entry = list[0];
    while (entry != __null) {
        var address = ((entry + 32) as __ptr<__ptr<u8>>)[0];
        if (address != __null) {
            if (_io_sys_sockaddr_family(address) != 0) {
                var found = _io_sockaddr_read(address);
                out.append(SocketAddress(found.address(), port));
            }
        }
        entry = ((entry + 40) as __ptr<__ptr<u8>>)[0];
    }
    FreeAddrInfoW(list[0]);
    _pep_free(list);
    return IoResult<SocketAddress[]>.ok(out);
}
