# POSIX (Linux, macOS) socket layer for io. Every declaration carries
# [Target(OS(Linux) || OS(Mac))] or a narrower target; socket_windows.pep
# and socket_wasi.pep declare the same `_io_sys_*` socket functions with the
# same signatures for Windows and WASI. Like sys_posix.pep, these are
# exported to the other io files only.
#
# Linux and macOS differ in the socket option numbers, the AF_INET6 value,
# the sockaddr header (a 16-bit family on Linux, a length byte and a family
# byte on macOS), the addrinfo field order, and how close-on-exec and
# SIGPIPE are handled: Linux passes SOCK_CLOEXEC and MSG_NOSIGNAL, macOS sets
# FD_CLOEXEC and SO_NOSIGPIPE on each new socket.

import "address";
import "socket";
import "sys_posix";
import "types";
import "wait";

# ── C functions ──────────────────────────────────────────────────────────────

[Target(OS(Linux) || OS(Mac))]
extern int socket(int domain, int kind, int protocol);
[Target(OS(Linux) || OS(Mac))]
extern int bind(int fd, void* address, uint length);
[Target(OS(Linux) || OS(Mac))]
extern int listen(int fd, int backlog);
[Target(OS(Linux) || OS(Mac))]
extern int connect(int fd, void* address, uint length);
[Target(OS(Linux) || OS(Mac))]
extern long recv(int fd, void* buffer, ulong length, int flags);
[Target(OS(Linux) || OS(Mac))]
extern long send(int fd, void* buffer, ulong length, int flags);
[Target(OS(Linux) || OS(Mac))]
extern long recvfrom(int fd, void* buffer, ulong length, int flags, void* address, uint* address_length);
[Target(OS(Linux) || OS(Mac))]
extern long sendto(int fd, void* buffer, ulong length, int flags, void* address, uint address_length);
[Target(OS(Linux) || OS(Mac))]
extern int shutdown(int fd, int how);
[Target(OS(Linux) || OS(Mac))]
extern int getsockopt(int fd, int level, int name, void* value, uint* length);
[Target(OS(Linux) || OS(Mac))]
extern int poll(void* descriptors, ulong count, int timeout);
[Target(OS(Linux) || OS(Mac))]
extern int setsockopt(int fd, int level, int name, void* value, uint length);
[Target(OS(Linux) || OS(Mac))]
extern int getsockname(int fd, void* address, uint* length);
[Target(OS(Linux) || OS(Mac))]
extern int getpeername(int fd, void* address, uint* length);
[Target(OS(Linux) || OS(Mac))]
extern int getaddrinfo(char* node, char* service, void* hints, void* result);
[Target(OS(Linux) || OS(Mac))]
extern void freeaddrinfo(void* list);
[Target(OS(Linux) || OS(Mac))]
extern char* gai_strerror(int code);
[Target(OS(Linux))]
extern int accept4(int fd, void* address, uint* length, int flags);
[Target(OS(Mac))]
extern int accept(int fd, void* address, uint* length);
[Target(OS(Mac))]
extern int fcntl(int fd, int command, ...);

# ── Constants ────────────────────────────────────────────────────────────────

[Target(OS(Linux) || OS(Mac))]
_io_af_inet(): int { return 2; }

[Target(OS(Linux))]
_io_af_inet6(): int { return 10; }

[Target(OS(Mac))]
_io_af_inet6(): int { return 30; }

[Target(OS(Linux))]
_io_sol_socket(): int { return 1; }

[Target(OS(Mac))]
_io_sol_socket(): int {
    return 65535;
}  # 0xffff

[Target(OS(Linux))]
_io_so_reuseaddr(): int { return 2; }

[Target(OS(Mac))]
_io_so_reuseaddr(): int { return 4; }

[Target(OS(Linux))]
_io_so_broadcast(): int { return 6; }

[Target(OS(Mac))]
_io_so_broadcast(): int {
    return 32;
}  # 0x20

[Target(OS(Linux))]
_io_sock_cloexec(): int {
    return 526336;
}  # SOCK_CLOEXEC | SOCK_NONBLOCK, or'ed into the type

[Target(OS(Mac))]
_io_sock_cloexec(): int {
    return 0;
}  # none: fcntl instead

[Target(OS(Linux))]
_io_so_error(): int { return 4; }

[Target(OS(Mac))]
_io_so_error(): int {
    return 4103;
}  # 0x1007

[Target(OS(Linux))]
_io_msg_nosignal(): int {
    return 16384;
}  # 0x4000

[Target(OS(Mac))]
_io_msg_nosignal(): int {
    return 0;
}  # none: SO_NOSIGPIPE instead

# ── Errors ───────────────────────────────────────────────────────────────────

[Target(OS(Linux))]
_io_sys_code_timed_out(): ErrorCode {
    return 110;
}  # ETIMEDOUT

[Target(OS(Mac))]
_io_sys_code_timed_out(): ErrorCode { return 60; }

# EAGAIN (the same value as EWOULDBLOCK): a non-blocking call would block.
[Target(OS(Linux))]
_io_posix_would_block(code: ErrorCode): bool { return code == 11; }

[Target(OS(Mac))]
_io_posix_would_block(code: ErrorCode): bool { return code == 35; }

# EINPROGRESS: a non-blocking connect has started.
[Target(OS(Linux))]
_io_posix_in_progress(code: ErrorCode): bool { return code == 115; }

[Target(OS(Mac))]
_io_posix_in_progress(code: ErrorCode): bool { return code == 36; }

# Code for a stream that ended before the bytes asked for: EIO.
[Target(OS(Linux) || OS(Mac))]
_io_sys_code_unexpected_end(): ErrorCode { return 5; }

# getaddrinfo's EAI_NONAME and EAI_NODATA: the name has no address.
[Target(OS(Linux))]
_io_eai_no_address(code: int): bool { return code == -2 || code == -5; }

[Target(OS(Mac))]
_io_eai_no_address(code: int): bool { return code == 8 || code == 7; }

# EAI_SYSTEM: the reason is in errno.
[Target(OS(Linux))]
_io_eai_system(code: int): bool { return code == -11; }

[Target(OS(Mac))]
_io_eai_system(code: int): bool { return code == 11; }

# The socket call's result: -1 means failure with the reason in errno.
[Target(OS(Linux) || OS(Mac))]
_io_socket_check(rc: int): IoResult<void> {
    return _io_posix_check(rc);
}

# ── Handles ──────────────────────────────────────────────────────────────────

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_invalid(): SocketHandle {
    return -1;
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_valid(h: SocketHandle): bool {
    return h >= 0;
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_close(h: SocketHandle): IoResult<void> {
    _io_socket_forget(h);
    return _io_sys_close(h);
}

# ── sockaddr ─────────────────────────────────────────────────────────────────

# The header of a sockaddr_in / sockaddr_in6: Linux has a 16-bit family at 0;
# macOS a length byte at 0 and a family byte at 1.
[Target(OS(Linux))]
_io_sys_sockaddr_header(buffer: __ptr<u8>, v6: bool, length: int) {
    var family = _io_af_inet();
    if (v6) {
        family = _io_af_inet6();
    }
    unsafe_cast<__ptr<u16>>(buffer)[0] = family as u16;
}

[Target(OS(Mac))]
_io_sys_sockaddr_header(buffer: __ptr<u8>, v6: bool, length: int) {
    var family = _io_af_inet();
    if (v6) {
        family = _io_af_inet6();
    }
    buffer[0] = length as u8;
    buffer[1] = family as u8;
}

# 4 for IPv4, 6 for IPv6, 0 for any other family.
[Target(OS(Linux))]
_io_sys_sockaddr_family(buffer: __ptr<u8>): int {
    var family = unsafe_cast<__ptr<u16>>(buffer)[0] as int;
    if (family == _io_af_inet()) {
        return 4;
    }
    if (family == _io_af_inet6()) {
        return 6;
    }
    return 0;
}

[Target(OS(Mac))]
_io_sys_sockaddr_family(buffer: __ptr<u8>): int {
    var family = buffer[1] as int;
    if (family == _io_af_inet()) {
        return 4;
    }
    if (family == _io_af_inet6()) {
        return 6;
    }
    return 0;
}

# sockaddr_un: the header as for sockaddr_in (family AF_UNIX, 1), then the
# path, NUL-terminated, at 2: at most 108 bytes on Linux, 104 on macOS.
[Target(OS(Linux))]
_io_sys_sockaddr_unix_header(buffer: __ptr<u8>, length: int) {
    unsafe_cast<__ptr<u16>>(buffer)[0] = 1;
}

[Target(OS(Mac))]
_io_sys_sockaddr_unix_header(buffer: __ptr<u8>, length: int) {
    buffer[0] = length as u8;
    buffer[1] = 1;
}

[Target(OS(Linux))]
_io_sys_unix_path_capacity(): ulong { return 108; }

[Target(OS(Mac))]
_io_sys_unix_path_capacity(): ulong { return 104; }

# ── Socket calls ─────────────────────────────────────────────────────────────

# A new non-blocking, close-on-exec socket (SOCK_STREAM 1 or SOCK_DGRAM 2)
# that never raises SIGPIPE. Every socket is non-blocking: a call that would
# block waits in `_io_socket_wait` and tries again.
[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_open(v6: bool, stream: bool): IoResult<SocketHandle> {
    var family = _io_af_inet();
    if (v6) {
        family = _io_af_inet6();
    }
    var kind = 2;
    if (stream) {
        kind = 1;
    }
    var fd = socket(family, kind | _io_sock_cloexec(), 0);
    if (fd < 0) {
        return IoResult<SocketHandle>.err(IoError.last());
    }
    _io_posix_socket_setup(fd);
    return IoResult<SocketHandle>.ok(fd);
}

# A new non-blocking, close-on-exec Unix domain stream socket (AF_UNIX 1,
# SOCK_STREAM 1) that never raises SIGPIPE.
[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_open_unix(): IoResult<SocketHandle> {
    var fd = socket(1, 1 | _io_sock_cloexec(), 0);
    if (fd < 0) {
        return IoResult<SocketHandle>.err(IoError.last());
    }
    _io_posix_socket_setup(fd);
    return IoResult<SocketHandle>.ok(fd);
}

# macOS: close-on-exec, non-blocking and SO_NOSIGPIPE, which Linux gets
# from the type and send flags.
[Target(OS(Linux))]
_io_posix_socket_setup(fd: int) {}

[Target(OS(Mac))]
_io_posix_socket_setup(fd: int) {
    fcntl(fd, 2, 1);                               # F_SETFD, FD_CLOEXEC
    fcntl(fd, 4, 4);                               # F_SETFL, O_NONBLOCK
    _io_posix_set_int_option(fd, 65535, 4130, 1);  # SOL_SOCKET, SO_NOSIGPIPE (0x1022)
}

[Target(OS(Linux) || OS(Mac))]
_io_posix_set_int_option(fd: int, level: int, name: int, value: int): IoResult<void> {
    var slot = _pep_malloc(4) as __ptr<int>;
    slot[0] = value;
    var rc = setsockopt(fd, level, name, slot, 4);
    var result = _io_socket_check(rc);
    _pep_free(slot);
    return result;
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_set_reuse_address(h: SocketHandle): IoResult<void> {
    return _io_posix_set_int_option(h, _io_sol_socket(), _io_so_reuseaddr(), 1);
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_set_no_delay(h: SocketHandle, enabled: bool): IoResult<void> {
    return _io_posix_set_int_option(h, 6, 1, enabled ? 1 : 0);  # IPPROTO_TCP, TCP_NODELAY
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_set_broadcast(h: SocketHandle, enabled: bool): IoResult<void> {
    return _io_posix_set_int_option(h, _io_sol_socket(), _io_so_broadcast(), enabled ? 1 : 0);
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_bind(h: SocketHandle, address: SocketAddress): IoResult<void> {
    var sockaddr = _io_sockaddr_write(address);
    return _io_sys_socket_bind_raw(h, sockaddr._bytes, sockaddr._length);
}

# Binds `h` to the `length`-byte sockaddr at `buffer`, of any family.
[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_bind_raw(h: SocketHandle, buffer: __ptr<u8>, length: int): IoResult<void> {
    return _io_socket_check(bind(h, buffer, length as uint));
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_listen(h: SocketHandle, backlog: int): IoResult<void> {
    return _io_socket_check(listen(h, backlog));
}

# A non-blocking connect returns EINPROGRESS (or EINTR, after which the
# connection carries on too); it has finished when the socket is writable,
# and SO_ERROR says how.
[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_connect(h: SocketHandle, address: SocketAddress): IoResult<void> {
    var sockaddr = _io_sockaddr_write(address);
    return _io_sys_socket_connect_raw(h, sockaddr._bytes, sockaddr._length);
}

# Connects `h` to the `length`-byte sockaddr at `buffer`, of any family.
[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_connect_raw(h: SocketHandle, buffer: __ptr<u8>, length: int): IoResult<void> {
    var rc = connect(h, buffer, length as uint);
    if (rc == 0) {
        return _io_ok_void();
    }
    var e = IoError.last();
    if (!_io_posix_in_progress(e.code) && !e.is_interrupted()) {
        return IoResult<void>.err(e);
    }
    var waited = _io_socket_wait(h, _IO_WRITABLE);
    if (waited.is_err()) {
        return waited;
    }
    var slot = _pep_malloc(8) as __ptr<int>;
    var size = unsafe_cast<__ptr<uint>>(slot + 1);
    slot[0] = 0;
    size[0] = 4;
    var got = getsockopt(h, _io_sol_socket(), _io_so_error(), slot, size);
    var code = slot[0];
    _pep_free(slot);
    if (got != 0) {
        return _io_posix_err_none();
    }
    if (code != 0) {
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    return _io_ok_void();
}

# Blocks the thread until `h` is ready for `interest` (poll(2)).
[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_poll(h: SocketHandle, interest: int): IoResult<void> {
    var buffer = _IoBuffer(8);
    var descriptor = unsafe_cast<__ptr<int>>(buffer._bytes);
    var events = unsafe_cast<__ptr<u16>>(buffer._bytes);
    descriptor[0] = h;
    events[2] = 1;  # POLLIN
    if (interest == _IO_WRITABLE) {
        events[2] = 4;  # POLLOUT
    }
    events[3] = 0;
    while (true) {
        if (poll(descriptor, 1, -1) >= 0) {
            return _io_ok_void();
        }
        var e = IoError.last();
        if (!e.is_interrupted()) {
            return IoResult<void>.err(e);
        }
    }
    return _io_ok_void();
}

# After a failed call with error `code`: waits for `interest` when the call
# would block, and succeeds when the call should be tried again (it would
# have blocked, or a signal interrupted it); otherwise fails with the error
# to return. The error's message is looked up only then, since would-block
# is the common case.
[Target(OS(Linux) || OS(Mac))]
_io_posix_retry(h: SocketHandle, code: ErrorCode, interest: int): IoResult<void> {
    if (_io_posix_would_block(code)) {
        return _io_socket_wait(h, interest);
    }
    if (_io_sys_error_kind(code) == ErrorKind.Interrupted) {
        return _io_ok_void();
    }
    return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
}

# The accepted socket is non-blocking and close-on-exec like the others.
[Target(OS(Linux))]
_io_posix_accept(fd: int, address: __ptr<u8>, length: __ptr<uint>): int {
    return accept4(fd, address, length, _io_sock_cloexec());
}

[Target(OS(Mac))]
_io_posix_accept(fd: int, address: __ptr<u8>, length: __ptr<uint>): int {
    var accepted = accept(fd, address, length);
    if (accepted >= 0) {
        _io_posix_socket_setup(accepted);
    }
    return accepted;
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_accept(h: SocketHandle): IoResult<(SocketHandle, SocketAddress)> {
    var peer = _SockAddr();
    while (true) {
        var fd = _io_posix_accept(h, peer._bytes, peer._length_slot());
        if (fd >= 0) {
            return IoResult<(SocketHandle, SocketAddress)>.ok((fd, peer._read()));
        }
        var retry = _io_posix_retry(h, _io_sys_last_error(), _IO_READABLE);
        if (retry.is_err()) {
            return IoResult<(SocketHandle, SocketAddress)>.err(retry.error());
        }
    }
    return IoResult<(SocketHandle, SocketAddress)>.err(IoError(4, "interrupted"));
}

[Target(OS(Linux) || OS(Mac))]
export _io_sys_socket_receive(h: SocketHandle, destination: __ptr<u8>, n: ulong): IoResult<ulong> {
    # In a task on io_uring, the kernel receives when data arrives.
    var transferred = _io_task_socket_transfer(h, destination, _io_posix_max_rw(n), false);
    if (transferred.is_value()) {
        return transferred.value();
    }
    while (true) {
        var r = recv(h, destination, _io_posix_max_rw(n), 0);
        if (r >= 0) {
            return IoResult<ulong>.ok(r as ulong);
        }
        var retry = _io_posix_retry(h, _io_sys_last_error(), _IO_READABLE);
        if (retry.is_err()) {
            return IoResult<ulong>.err(retry.error());
        }
    }
    return IoResult<ulong>.ok(0);
}

[Target(OS(Linux) || OS(Mac))]
export _io_sys_socket_send(h: SocketHandle, source: __ptr<u8>, n: ulong): IoResult<ulong> {
    var transferred = _io_task_socket_transfer(h, source, _io_posix_max_rw(n), true);
    if (transferred.is_value()) {
        return transferred.value();
    }
    while (true) {
        var r = send(h, source, _io_posix_max_rw(n), _io_msg_nosignal());
        if (r >= 0) {
            return IoResult<ulong>.ok(r as ulong);
        }
        var retry = _io_posix_retry(h, _io_sys_last_error(), _IO_WRITABLE);
        if (retry.is_err()) {
            return IoResult<ulong>.err(retry.error());
        }
    }
    return IoResult<ulong>.ok(0);
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_send_to(h: SocketHandle, source: __ptr<u8>, n: ulong, address: SocketAddress): IoResult<ulong> {
    var sockaddr = _io_sockaddr_write(address);
    while (true) {
        var r = sendto(h, source, _io_posix_max_rw(n), _io_msg_nosignal(), sockaddr._bytes, sockaddr._length as uint);
        if (r >= 0) {
            return IoResult<ulong>.ok(r as ulong);
        }
        var retry = _io_posix_retry(h, _io_sys_last_error(), _IO_WRITABLE);
        if (retry.is_err()) {
            return IoResult<ulong>.err(retry.error());
        }
    }
    return IoResult<ulong>.ok(0);
}

# A datagram longer than `n` is truncated to `n` bytes; the rest is lost.
[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_receive_from(h: SocketHandle, destination: __ptr<u8>, n: ulong): IoResult<(ulong, SocketAddress)> {
    var from = _SockAddr();
    while (true) {
        var r = recvfrom(h, destination, _io_posix_max_rw(n), 0, from._bytes, from._length_slot());
        if (r >= 0) {
            return IoResult<(ulong, SocketAddress)>.ok((r as ulong, from._read()));
        }
        var retry = _io_posix_retry(h, _io_sys_last_error(), _IO_READABLE);
        if (retry.is_err()) {
            return IoResult<(ulong, SocketAddress)>.err(retry.error());
        }
    }
    return IoResult<(ulong, SocketAddress)>.err(IoError(4, "interrupted"));
}

# how: 0 reading, 1 writing, 2 both (SHUT_RD, SHUT_WR, SHUT_RDWR).
[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_shutdown(h: SocketHandle, how: int): IoResult<void> {
    return _io_socket_check(shutdown(h, how));
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_local_address(h: SocketHandle): IoResult<SocketAddress> {
    var address = _SockAddr();
    return _io_posix_address_result(getsockname(h, address._bytes, address._length_slot()), address);
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_socket_peer_address(h: SocketHandle): IoResult<SocketAddress> {
    var address = _SockAddr();
    return _io_posix_address_result(getpeername(h, address._bytes, address._length_slot()), address);
}

# The address getsockname/getpeername wrote into `address`, or errno.
[Target(OS(Linux) || OS(Mac))]
_io_posix_address_result(rc: int, address: _SockAddr): IoResult<SocketAddress> {
    if (rc != 0) {
        return IoResult<SocketAddress>.err(IoError.last());
    }
    return IoResult<SocketAddress>.ok(address._read());
}

# ── Name resolution ──────────────────────────────────────────────────────────
# struct addrinfo: ai_flags @0, ai_family @4, ai_socktype @8, ai_protocol @12,
# ai_addrlen @16, then glibc has ai_addr @24 and ai_canonname @32, macOS and
# Android's bionic (both BSD-derived) the two the other way round; ai_next
# @40; 48 bytes in all.

[Target(OS(Linux) && !OS(Android))]
_io_addrinfo_address_offset(): ulong { return 24; }

[Target(OS(Mac) || OS(Android))]
_io_addrinfo_address_offset(): ulong { return 32; }

[Target(OS(Linux) || OS(Mac))]
_io_sys_resolve(host: String, port: u16): IoResult<SocketAddress[]> {
    var hints = _IoBuffer(48);
    unsafe_cast<__ptr<int>>(hints._bytes)[2] = 1;  # ai_socktype = SOCK_STREAM: one entry per address
    var result = _IoBuffer(8);
    var list = unsafe_cast<__ptr<__ptr<u8>>>(result._bytes);
    var rc = getaddrinfo(host.c_str(), __null, hints._bytes, list);
    if (rc != 0) {
        if (_io_eai_system(rc)) {
            return IoResult<SocketAddress[]>.err(IoError.last());
        }
        var message = "failed to resolve '" + host + "': " + String(gai_strerror(rc));
        if (_io_eai_no_address(rc)) {
            return IoResult<SocketAddress[]>.err(IoError(_io_sys_code_not_found(), message));
        }
        return IoResult<SocketAddress[]>.err(IoError(5, message));  # EIO
    }
    var out = Array<SocketAddress>();
    var entry = list[0];
    while (entry != __null) {
        var address = unsafe_cast<__ptr<__ptr<u8>>>(entry + _io_addrinfo_address_offset())[0];
        if (address != __null) {
            if (_io_sys_sockaddr_family(address) != 0) {
                var found = _io_sockaddr_read(address);
                out.append(SocketAddress(found.address(), port));
            }
        }
        entry = unsafe_cast<__ptr<__ptr<u8>>>(entry + 40)[0];
    }
    freeaddrinfo(list[0]);
    return IoResult<SocketAddress[]>.ok(out);
}
