# The tls layer for WASI (WebAssembly): the same `_tls_sys_*` functions as
# openssl.pep and schannel.pep, each with [Target(OS(Wasi))]. WASI preview
# 1 has no sockets to secure (see io's socket_wasi.pep), so making a
# context fails with ENOTSUP and nothing else is ever reached.

import io;

[Target(OS(Wasi))]
_tls_sys_code_protocol(): io.ErrorCode {
    return 65;
}  # EPROTO

[Target(OS(Wasi))]
_tls_error(message: String): io.IoError {
    return io.IoError(_tls_sys_code_protocol(), message);
}

[Target(OS(Wasi))]
_tls_wasi_unsupported(): io.IoError {
    return io.IoError(58, "TLS is not supported on WASI");  # ENOTSUP
}

[Target(OS(Wasi))]
_tls_sys_client_context(): io.IoResult<__ptr<void>> {
    return io.IoResult<__ptr<void>>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_server_context(chain: io.Path, key: io.Path): io.IoResult<__ptr<void>> {
    return io.IoResult<__ptr<void>>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_add_root(context: __ptr<void>, path: io.Path): io.IoResult<void> {
    return io.IoResult<void>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_set_identity(context: __ptr<void>, chain: io.Path, key: io.Path): io.IoResult<void> {
    return io.IoResult<void>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_require_client_certificate(context: __ptr<void>, roots: io.Path): io.IoResult<void> {
    return io.IoResult<void>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_set_protocols(context: __ptr<void>, list: u8[], server: bool): io.IoResult<void> {
    return io.IoResult<void>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_protocol(session: __ptr<void>): String {
    return "";
}

[Target(OS(Wasi))]
_tls_sys_context_free(context: __ptr<void>) {}

[Target(OS(Wasi))]
_tls_sys_connect(context: __ptr<void>, h: io.SocketHandle, host: String): io.IoResult<__ptr<void>> {
    return io.IoResult<__ptr<void>>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_accept(context: __ptr<void>, h: io.SocketHandle): io.IoResult<__ptr<void>> {
    return io.IoResult<__ptr<void>>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_read(session: __ptr<void>, destination: __ptr<u8>, n: ulong): io.IoResult<ulong> {
    return io.IoResult<ulong>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_write(session: __ptr<void>, source: __ptr<u8>, n: ulong): io.IoResult<ulong> {
    return io.IoResult<ulong>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_shutdown(session: __ptr<void>): io.IoResult<void> {
    return io.IoResult<void>.err(_tls_wasi_unsupported());
}

[Target(OS(Wasi))]
_tls_sys_session_free(session: __ptr<void>) {}
