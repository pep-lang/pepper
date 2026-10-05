# WASI (WebAssembly) socket layer for io: the same `_io_sys_*` socket
# functions as socket_posix.pep and socket_windows.pep, each with
# [Target(OS(Wasi))]. WASI preview 1 cannot open, bind or connect a
# socket, or resolve a name, so every call that would make or use one fails
# with ENOTSUP; the address helpers write the Linux layout, which nothing
# reads back.

import "address";
import "socket";
import "sys_posix";
import "types";
import "wait";

[Target(OS(Wasi))]
_io_sys_code_timed_out(): ErrorCode {
    return 73;
}  # ETIMEDOUT

[Target(OS(Wasi))]
_io_sys_code_unexpected_end(): ErrorCode {
    return 29;
}  # EIO

# What every socket call returns: sockets are not part of WASI preview 1.
[Target(OS(Wasi))]
_io_wasi_no_sockets(): IoError {
    return IoError(58, "sockets are not supported on WASI");  # ENOTSUP
}

# ── Handles ──────────────────────────────────────────────────────────────────

[Target(OS(Wasi))]
_io_sys_socket_invalid(): SocketHandle {
    return -1;
}

[Target(OS(Wasi))]
_io_sys_socket_valid(h: SocketHandle): bool {
    return h >= 0;
}

[Target(OS(Wasi))]
_io_sys_socket_close(h: SocketHandle): IoResult<void> {
    _io_socket_forget(h);
    return _io_sys_close(h);
}

# ── sockaddr ─────────────────────────────────────────────────────────────────

[Target(OS(Wasi))]
_io_sys_sockaddr_header(buffer: __ptr<u8>, v6: bool, length: int) {
    unsafe_cast<__ptr<u16>>(buffer)[0] = v6 ? 10 : 2;
}

[Target(OS(Wasi))]
_io_sys_sockaddr_family(buffer: __ptr<u8>): int {
    var family = unsafe_cast<__ptr<u16>>(buffer)[0] as int;
    if (family == 2) {
        return 4;
    }
    if (family == 10) {
        return 6;
    }
    return 0;
}

[Target(OS(Wasi))]
_io_sys_sockaddr_unix_header(buffer: __ptr<u8>, length: int) {
    unsafe_cast<__ptr<u16>>(buffer)[0] = 1;
}

[Target(OS(Wasi))]
_io_sys_unix_path_capacity(): ulong {
    return 108;
}

# ── Socket calls ─────────────────────────────────────────────────────────────

[Target(OS(Wasi))]
_io_sys_socket_open(v6: bool, stream: bool): IoResult<SocketHandle> {
    return IoResult<SocketHandle>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_open_unix(): IoResult<SocketHandle> {
    return IoResult<SocketHandle>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_set_reuse_address(h: SocketHandle): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_set_no_delay(h: SocketHandle, enabled: bool): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_set_broadcast(h: SocketHandle, enabled: bool): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_bind(h: SocketHandle, address: SocketAddress): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_bind_raw(h: SocketHandle, buffer: __ptr<u8>, length: int): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_listen(h: SocketHandle, backlog: int): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_connect(h: SocketHandle, address: SocketAddress): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_connect_raw(h: SocketHandle, buffer: __ptr<u8>, length: int): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_poll(h: SocketHandle, interest: int, timeout: ulong): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_accept(h: SocketHandle): IoResult<(SocketHandle, SocketAddress)> {
    return IoResult<(SocketHandle, SocketAddress)>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
export _io_sys_socket_receive(h: SocketHandle, destination: __ptr<u8>, n: ulong): IoResult<ulong> {
    return IoResult<ulong>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
export _io_sys_socket_send(h: SocketHandle, source: __ptr<u8>, n: ulong): IoResult<ulong> {
    return IoResult<ulong>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_send_to(h: SocketHandle, source: __ptr<u8>, n: ulong, address: SocketAddress): IoResult<ulong> {
    return IoResult<ulong>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_receive_from(h: SocketHandle, destination: __ptr<u8>, n: ulong): IoResult<(ulong, SocketAddress)> {
    return IoResult<(ulong, SocketAddress)>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_shutdown(h: SocketHandle, how: int): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_local_address(h: SocketHandle): IoResult<SocketAddress> {
    return IoResult<SocketAddress>.err(_io_wasi_no_sockets());
}

[Target(OS(Wasi))]
_io_sys_socket_peer_address(h: SocketHandle): IoResult<SocketAddress> {
    return IoResult<SocketAddress>.err(_io_wasi_no_sockets());
}

# ── Name resolution ──────────────────────────────────────────────────────────

[Target(OS(Wasi))]
_io_sys_resolve(host: String, port: u16): IoResult<SocketAddress[]> {
    return IoResult<SocketAddress[]>.err(_io_wasi_no_sockets());
}

# ── Network interfaces ───────────────────────────────────────────────────────

[Target(OS(Wasi))]
_io_sys_interface_index(name: String): uint {
    return 0;
}

[Target(OS(Wasi))]
_io_sys_interface_name(index: uint): String {
    return "";
}
