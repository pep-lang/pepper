# The OpenSSL 3 layer for tls on Linux and macOS. Every declaration carries
# [Target(!OS(Windows))]; schannel.pep declares the same `_tls_sys_*`
# functions for Windows.
#
# libssl is opened at run time (dlopen) the first time a context is made, so
# a program that imports tls links against nothing extra and needs no
# library search path for Homebrew's OpenSSL. `_OpenSsl` holds the functions
# it uses as C function pointers.
#
# The connection's bytes go through a custom BIO whose read and write call
# the io socket layer (`_io_sys_socket_receive` / `_send`). Those wait when
# the socket would block, parking a task inside the callback, so OpenSSL
# never sees SSL_ERROR_WANT_READ/WRITE and every call here reads like
# blocking code. An io error in a callback (a reset, a cancelled task) is
# kept in the session and returned in place of OpenSSL's report.

import async;
import io;
import "schannel";

[Target(OS(Linux))]
[Link("dl")]
extern void* dlopen(char* path, int flags);
[Target(!OS(Windows))]
extern void* dlsym(void* handle, char* name);

# The libssl names to try, in order.
[Target(OS(Linux))]
_tls_openssl_paths(): String[] {
    return ["libssl.so.3"];
}

[Target(OS(Mac))]
extern void* dlopen(char* path, int flags);

[Target(OS(Mac))]
_tls_openssl_paths(): String[] {
    return [
        "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib",
        "/usr/local/opt/openssl@3/lib/libssl.3.dylib",
        "/opt/local/lib/libssl.3.dylib",
        "libssl.3.dylib",
    ];
}

# The OpenSSL functions tls calls, or none when libssl could not be opened.
[Target(!OS(Windows))]
[Shared]
export struct _OpenSsl {
    # Whether libssl was found; every other field is null otherwise.
    const _loaded: bool;
    const _client_method: extern () => __ptr<void>;
    const _server_method: extern () => __ptr<void>;
    const _context_new: extern (__ptr<void>) => __ptr<void>;
    const _context_free: extern (__ptr<void>) => void;
    const _context_ctrl: extern (__ptr<void>, int, long, __ptr<void>) => long;
    const _context_set_options: extern (__ptr<void>, ulong) => ulong;
    const _context_default_roots: extern (__ptr<void>) => int;
    const _context_set_verify: extern (__ptr<void>, int, __ptr<void>) => void;
    const _context_load_roots: extern (__ptr<void>, __ptr<void>, __ptr<void>) => int;
    const _context_use_chain: extern (__ptr<void>, __ptr<void>) => int;
    const _context_use_key: extern (__ptr<void>, __ptr<void>, int) => int;
    const _context_check_key: extern (__ptr<void>) => int;
    const _ssl_new: extern (__ptr<void>) => __ptr<void>;
    const _ssl_free: extern (__ptr<void>) => void;
    const _ssl_ctrl: extern (__ptr<void>, int, long, __ptr<void>) => long;
    const _ssl_set_bio: extern (__ptr<void>, __ptr<void>, __ptr<void>) => void;
    const _ssl_set_host: extern (__ptr<void>, __ptr<void>) => int;
    const _ssl_param: extern (__ptr<void>) => __ptr<void>;
    const _ssl_connect: extern (__ptr<void>) => int;
    const _ssl_accept: extern (__ptr<void>) => int;
    const _ssl_read: extern (__ptr<void>, __ptr<void>, int) => int;
    const _ssl_write: extern (__ptr<void>, __ptr<void>, int) => int;
    const _ssl_shutdown: extern (__ptr<void>) => int;
    const _ssl_error: extern (__ptr<void>, int) => int;
    const _ssl_verify_result: extern (__ptr<void>) => long;
    const _param_set_ip: extern (__ptr<void>, __ptr<void>) => int;
    const _verify_error_string: extern (long) => __ptr<void>;
    const _error_get: extern () => ulong;
    const _error_string: extern (ulong, __ptr<void>, ulong) => void;
    const _error_clear: extern () => void;
    const _bio_method_new: extern (int, __ptr<void>) => __ptr<void>;
    const _bio_method_set_write: extern (__ptr<void>, __ptr<void>) => int;
    const _bio_method_set_read: extern (__ptr<void>, __ptr<void>) => int;
    const _bio_method_set_ctrl: extern (__ptr<void>, __ptr<void>) => int;
    const _bio_new_index: extern () => int;
    const _bio_new: extern (__ptr<void>) => __ptr<void>;
    const _bio_set_data: extern (__ptr<void>, __ptr<void>) => void;
    const _bio_get_data: extern (__ptr<void>) => __ptr<void>;
    const _bio_set_init: extern (__ptr<void>, int) => void;
    # The BIO_meth_set_* setters take the callbacks as untyped addresses
    # (`__function_pointer`): a C function pointer type as a parameter of
    # another is reported as an unknown type.
    # The BIO_METHOD every connection's BIO uses, made once.
    const _bio_method: __ptr<void>;

    construct() {
        var handle: __ptr<void> = __null;
        for (var path in _tls_openssl_paths()) {
            handle = dlopen(path.c_str(), 2);  # RTLD_NOW
            if (handle != __null) {
                break;
            }
        }
        _loaded = handle != __null;
        if (_loaded) {
            _client_method = _tls_symbol(handle, "TLS_client_method") as extern () => __ptr<void>;
            _server_method = _tls_symbol(handle, "TLS_server_method") as extern () => __ptr<void>;
            _context_new = _tls_symbol(handle, "SSL_CTX_new") as extern (__ptr<void>) => __ptr<void>;
            _context_free = _tls_symbol(handle, "SSL_CTX_free") as extern (__ptr<void>) => void;
            _context_ctrl = _tls_symbol(handle, "SSL_CTX_ctrl") as extern (__ptr<void>, int, long, __ptr<void>) => long;
            _context_set_options = _tls_symbol(handle, "SSL_CTX_set_options") as extern (__ptr<void>, ulong) => ulong;
            _context_default_roots = _tls_symbol(
                handle, "SSL_CTX_set_default_verify_paths"
            ) as extern (__ptr<void>) => int;
            _context_set_verify = _tls_symbol(
                handle, "SSL_CTX_set_verify"
            ) as extern (__ptr<void>, int, __ptr<void>) => void;
            _context_load_roots = _tls_symbol(
                handle, "SSL_CTX_load_verify_locations"
            ) as extern (__ptr<void>, __ptr<void>, __ptr<void>) => int;
            _context_use_chain = _tls_symbol(
                handle, "SSL_CTX_use_certificate_chain_file"
            ) as extern (__ptr<void>, __ptr<void>) => int;
            _context_use_key = _tls_symbol(
                handle, "SSL_CTX_use_PrivateKey_file"
            ) as extern (__ptr<void>, __ptr<void>, int) => int;
            _context_check_key = _tls_symbol(handle, "SSL_CTX_check_private_key") as extern (__ptr<void>) => int;
            _ssl_new = _tls_symbol(handle, "SSL_new") as extern (__ptr<void>) => __ptr<void>;
            _ssl_free = _tls_symbol(handle, "SSL_free") as extern (__ptr<void>) => void;
            _ssl_ctrl = _tls_symbol(handle, "SSL_ctrl") as extern (__ptr<void>, int, long, __ptr<void>) => long;
            _ssl_set_bio = _tls_symbol(handle, "SSL_set_bio") as extern (__ptr<void>, __ptr<void>, __ptr<void>) => void;
            _ssl_set_host = _tls_symbol(handle, "SSL_set1_host") as extern (__ptr<void>, __ptr<void>) => int;
            _ssl_param = _tls_symbol(handle, "SSL_get0_param") as extern (__ptr<void>) => __ptr<void>;
            _ssl_connect = _tls_symbol(handle, "SSL_connect") as extern (__ptr<void>) => int;
            _ssl_accept = _tls_symbol(handle, "SSL_accept") as extern (__ptr<void>) => int;
            _ssl_read = _tls_symbol(handle, "SSL_read") as extern (__ptr<void>, __ptr<void>, int) => int;
            _ssl_write = _tls_symbol(handle, "SSL_write") as extern (__ptr<void>, __ptr<void>, int) => int;
            _ssl_shutdown = _tls_symbol(handle, "SSL_shutdown") as extern (__ptr<void>) => int;
            _ssl_error = _tls_symbol(handle, "SSL_get_error") as extern (__ptr<void>, int) => int;
            _ssl_verify_result = _tls_symbol(handle, "SSL_get_verify_result") as extern (__ptr<void>) => long;
            _param_set_ip = _tls_symbol(
                handle, "X509_VERIFY_PARAM_set1_ip_asc"
            ) as extern (__ptr<void>, __ptr<void>) => int;
            _verify_error_string = _tls_symbol(handle, "X509_verify_cert_error_string") as extern (long) => __ptr<void>;
            _error_get = _tls_symbol(handle, "ERR_get_error") as extern () => ulong;
            _error_string = _tls_symbol(handle, "ERR_error_string_n") as extern (ulong, __ptr<void>, ulong) => void;
            _error_clear = _tls_symbol(handle, "ERR_clear_error") as extern () => void;
            _bio_method_new = _tls_symbol(handle, "BIO_meth_new") as extern (int, __ptr<void>) => __ptr<void>;
            _bio_method_set_write = _tls_symbol(
                handle, "BIO_meth_set_write"
            ) as extern (__ptr<void>, __ptr<void>) => int;
            _bio_method_set_read = _tls_symbol(handle, "BIO_meth_set_read") as extern (__ptr<void>, __ptr<void>) => int;
            _bio_method_set_ctrl = _tls_symbol(handle, "BIO_meth_set_ctrl") as extern (__ptr<void>, __ptr<void>) => int;
            _bio_new_index = _tls_symbol(handle, "BIO_get_new_index") as extern () => int;
            _bio_new = _tls_symbol(handle, "BIO_new") as extern (__ptr<void>) => __ptr<void>;
            _bio_set_data = _tls_symbol(handle, "BIO_set_data") as extern (__ptr<void>, __ptr<void>) => void;
            _bio_get_data = _tls_symbol(handle, "BIO_get_data") as extern (__ptr<void>) => __ptr<void>;
            _bio_set_init = _tls_symbol(handle, "BIO_set_init") as extern (__ptr<void>, int) => void;

            var method_new = _bio_method_new;
            var new_index = _bio_new_index;
            var name = "pepper socket";
            # BIO_TYPE_SOURCE_SINK (0x0400) marks a BIO that ends the chain.
            var method = method_new(new_index() | 1024, name.c_str());
            var set_write = _bio_method_set_write;
            var set_read = _bio_method_set_read;
            var set_ctrl = _bio_method_set_ctrl;
            set_write(method, __function_pointer(_tls_bio_write));
            set_read(method, __function_pointer(_tls_bio_read));
            set_ctrl(method, __function_pointer(_tls_bio_ctrl));
            _bio_method = method;
        }
    }
}

# The address of `name` in the opened library and its dependencies.
[Target(!OS(Windows))]
_tls_symbol(handle: __ptr<void>, name: String): __ptr<void> {
    return dlsym(handle, name.c_str());
}

[Target(!OS(Windows))]
const _tls_openssl = async.Lazy<_OpenSsl>(() => {
    return _OpenSsl();
});

# ── Sessions ─────────────────────────────────────────────────────────────────
# A session is a malloc'd block of three words: the SSL*, the socket, and a
# slot holding the io error a BIO callback met (null when none). The BIO's
# data points at the block.

[Target(!OS(Windows))]
_tls_session_ssl(session: __ptr<void>): __ptr<void> {
    __ptr<__ptr<void>> block = session;
    return block[0];
}

[Target(!OS(Windows))]
_tls_session_error(session: __ptr<void>): __ptr<io.IoError> {
    __ptr<ulong> block = session;
    return (block + 2) as __ptr<io.IoError>;
}

# The BIO callbacks. Each finds its session through the BIO's data.

[Target(!OS(Windows))]
_tls_bio_session(bio: __ptr<void>): __ptr<void> {
    var get_data = _tls_openssl.get()._bio_get_data;
    return get_data(bio);
}

[Target(!OS(Windows))]
_tls_bio_write(bio: __ptr<void>, data: __ptr<void>, n: int): int {
    var session = _tls_bio_session(bio);
    __ptr<ulong> block = session;
    var r = io._io_sys_socket_send(block[1] as io.SocketHandle, data as __ptr<u8>, n as ulong);
    if (r.is_err()) {
        _tls_session_error(session)[0] = r.error();
        return -1;
    }
    return r.value() as int;
}

[Target(!OS(Windows))]
_tls_bio_read(bio: __ptr<void>, data: __ptr<void>, n: int): int {
    var session = _tls_bio_session(bio);
    __ptr<ulong> block = session;
    var r = io._io_sys_socket_receive(block[1] as io.SocketHandle, data as __ptr<u8>, n as ulong);
    if (r.is_err()) {
        _tls_session_error(session)[0] = r.error();
        return -1;
    }
    return r.value() as int;
}

# Only BIO_CTRL_FLUSH (11) needs an answer: the writes are not buffered.
[Target(!OS(Windows))]
_tls_bio_ctrl(bio: __ptr<void>, command: int, number: long, pointer: __ptr<void>): long {
    return command == 11 ? 1 : 0;
}

# ── Errors ───────────────────────────────────────────────────────────────────

# EPROTO: the code of every TLS error.
[Target(OS(Linux))]
export _tls_sys_code_protocol(): io.ErrorCode { return 71; }

[Target(OS(Mac))]
export _tls_sys_code_protocol(): io.ErrorCode { return 100; }

[Target(!OS(Windows))]
export _tls_error(message: String): io.IoError {
    return io.IoError(_tls_sys_code_protocol(), message);
}

# The oldest error in OpenSSL's queue, with `what` in front; clears the
# queue.
[Target(!OS(Windows))]
_tls_openssl_error(what: String): io.IoError {
    var ssl = _tls_openssl.get();
    var get = ssl._error_get;
    var text = ssl._error_string;
    var clear = ssl._error_clear;
    var code = get();
    clear();
    if (code == 0) {
        return _tls_error(what);
    }
    __ptr<char> buffer = _pep_malloc(256);
    text(code, buffer, 256);
    var message = $"{what}: {String(buffer)}";
    _pep_free(buffer);
    return _tls_error(message);
}

# Why an SSL call on `session` that returned `rc` failed: the io error a
# callback met, the certificate check's reason, or OpenSSL's.
[Target(!OS(Windows))]
_tls_session_failure(session: __ptr<void>, rc: int, what: String): io.IoError {
    var ssl = _tls_openssl.get();
    var slot = _tls_session_error(session);
    if (slot[0] != __null) {
        var e = slot[0];
        slot[0] = __default<io.IoError>();
        var clear = ssl._error_clear;
        clear();
        return e;
    }
    var verify_result = ssl._ssl_verify_result;
    var verified = verify_result(_tls_session_ssl(session));
    if (verified != 0) {
        var reason = ssl._verify_error_string;
        var clear = ssl._error_clear;
        clear();
        return _tls_error($"certificate verify failed: {String(reason(verified) as __ptr<char>)}");
    }
    return _tls_openssl_error(what);
}

# ── Contexts ─────────────────────────────────────────────────────────────────

[Target(!OS(Windows))]
_tls_openssl_loaded(): io.IoResult<_OpenSsl> {
    var ssl = _tls_openssl.get();
    if (!ssl._loaded) {
        var names = "";
        for (var path in _tls_openssl_paths()) {
            names = names.size() > 0 ? $"{names}, {path}" : path;
        }
        return io.IoResult<_OpenSsl>.err(_tls_error($"OpenSSL 3 was not found (tried {names})"));
    }
    return io.IoResult<_OpenSsl>.ok(ssl);
}

# A new SSL_CTX for TLS 1.2 and later, or null.
[Target(!OS(Windows))]
_tls_context_new(ssl: _OpenSsl, server: bool): __ptr<void> {
    var method = ssl._client_method;
    if (server) {
        method = ssl._server_method;
    }
    var context_new = ssl._context_new;
    var context = context_new(method());
    if (context == __null) {
        return __null;
    }
    var ctrl = ssl._context_ctrl;
    ctrl(context, 123, 771, __null);  # SSL_CTRL_SET_MIN_PROTO_VERSION, TLS1_2_VERSION
    # SSL_MODE_ENABLE_PARTIAL_WRITE | SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER
    ctrl(context, 33, 3, __null);
    # SSL_OP_IGNORE_UNEXPECTED_EOF: a peer that closes without close_notify
    # ends the stream like a TCP close.
    var set_options = ssl._context_set_options;
    set_options(context, 128);
    return context;
}

# A client context that checks the server's certificate against the
# system's trusted roots.
[Target(!OS(Windows))]
export _tls_sys_client_context(): io.IoResult<__ptr<void>> {
    var loaded = _tls_openssl_loaded();
    if (loaded.is_err()) {
        return io.IoResult<__ptr<void>>.err(loaded.error());
    }
    var ssl = loaded.value();
    var context = _tls_context_new(ssl, false);
    if (context == __null) {
        return io.IoResult<__ptr<void>>.err(_tls_openssl_error("cannot create a TLS context"));
    }
    var default_roots = ssl._context_default_roots;
    default_roots(context);
    var set_verify = ssl._context_set_verify;
    set_verify(context, 1, __null);  # SSL_VERIFY_PEER
    return io.IoResult<__ptr<void>>.ok(context);
}

# A server context presenting the PEM certificate chain and private key.
[Target(!OS(Windows))]
export _tls_sys_server_context(chain: io.Path, key: io.Path): io.IoResult<__ptr<void>> {
    var loaded = _tls_openssl_loaded();
    if (loaded.is_err()) {
        return io.IoResult<__ptr<void>>.err(loaded.error());
    }
    var ssl = loaded.value();
    var context = _tls_context_new(ssl, true);
    if (context == __null) {
        return io.IoResult<__ptr<void>>.err(_tls_openssl_error("cannot create a TLS context"));
    }
    var use_chain = ssl._context_use_chain;
    var use_key = ssl._context_use_key;
    var check_key = ssl._context_check_key;
    var chain_text = chain.to_string();
    var key_text = key.to_string();
    var failure = "";
    if (use_chain(context, chain_text.c_str()) != 1) {
        failure = $"cannot load the certificate chain '{chain_text}'";
    } else if (use_key(context, key_text.c_str(), 1) != 1) {  # SSL_FILETYPE_PEM
        failure = $"cannot load the private key '{key_text}'";
    } else if (check_key(context) != 1) {
        failure = "the private key does not match the certificate";
    }
    if (failure.size() > 0) {
        var e = _tls_openssl_error(failure);
        var context_free = ssl._context_free;
        context_free(context);
        return io.IoResult<__ptr<void>>.err(e);
    }
    return io.IoResult<__ptr<void>>.ok(context);
}

# Also trusts the PEM certificates in `path`.
[Target(!OS(Windows))]
export _tls_sys_add_root(context: __ptr<void>, path: io.Path): io.IoResult<void> {
    var ssl = _tls_openssl.get();
    var load = ssl._context_load_roots;
    var text = path.to_string();
    if (load(context, text.c_str(), __null) != 1) {
        return io.IoResult<void>.err(_tls_openssl_error($"cannot load the certificates in '{text}'"));
    }
    return io.IoResult<void>.ok();
}

[Target(!OS(Windows))]
export _tls_sys_context_free(context: __ptr<void>) {
    var context_free = _tls_openssl.get()._context_free;
    context_free(context);
}

# ── Connections ──────────────────────────────────────────────────────────────

# A session for socket `h` on `context`, with its BIO; null on failure.
[Target(!OS(Windows))]
_tls_session_new(context: __ptr<void>, h: io.SocketHandle): __ptr<void> {
    var ssl = _tls_openssl.get();
    var ssl_new = ssl._ssl_new;
    var connection = ssl_new(context);
    if (connection == __null) {
        return __null;
    }
    __ptr<void> session = _pep_malloc(3 * sizeof<ulong>());
    __ptr<__ptr<void>> words = session;
    words[0] = connection;
    __ptr<ulong> numbers = session;
    numbers[1] = h as ulong;
    var bio_new = ssl._bio_new;
    var bio = bio_new(ssl._bio_method);
    var set_data = ssl._bio_set_data;
    var set_init = ssl._bio_set_init;
    set_data(bio, session);
    set_init(bio, 1);
    var set_bio = ssl._ssl_set_bio;
    set_bio(connection, bio, bio);
    return session;
}

# Runs the client handshake on socket `h`, checking that the certificate is
# for `host` (a name, or an IP address).
[Target(!OS(Windows))]
export _tls_sys_connect(context: __ptr<void>, h: io.SocketHandle, host: String): io.IoResult<__ptr<void>> {
    var session = _tls_session_new(context, h);
    if (session == __null) {
        return io.IoResult<__ptr<void>>.err(_tls_openssl_error("cannot create a TLS connection"));
    }
    var ssl = _tls_openssl.get();
    var connection = _tls_session_ssl(session);
    if (io.IpAddress.parse(host).is_ok()) {
        var param = ssl._ssl_param;
        var set_ip = ssl._param_set_ip;
        set_ip(param(connection), host.c_str());
    } else {
        var ctrl = ssl._ssl_ctrl;
        ctrl(connection, 55, 0, host.c_str());  # SSL_CTRL_SET_TLSEXT_HOSTNAME: SNI
        var set_host = ssl._ssl_set_host;
        set_host(connection, host.c_str());
    }
    var connect = ssl._ssl_connect;
    var rc = connect(connection);
    if (rc != 1) {
        var e = _tls_session_failure(session, rc, "TLS handshake failed");
        _tls_sys_session_free(session);
        return io.IoResult<__ptr<void>>.err(e);
    }
    return io.IoResult<__ptr<void>>.ok(session);
}

# Runs the server handshake on socket `h`.
[Target(!OS(Windows))]
export _tls_sys_accept(context: __ptr<void>, h: io.SocketHandle): io.IoResult<__ptr<void>> {
    var session = _tls_session_new(context, h);
    if (session == __null) {
        return io.IoResult<__ptr<void>>.err(_tls_openssl_error("cannot create a TLS connection"));
    }
    var accept = _tls_openssl.get()._ssl_accept;
    var rc = accept(_tls_session_ssl(session));
    if (rc != 1) {
        var e = _tls_session_failure(session, rc, "TLS handshake failed");
        _tls_sys_session_free(session);
        return io.IoResult<__ptr<void>>.err(e);
    }
    return io.IoResult<__ptr<void>>.ok(session);
}

# Reads up to `n` decrypted bytes into `destination`; 0 at the end of the
# stream.
[Target(!OS(Windows))]
export _tls_sys_read(session: __ptr<void>, destination: __ptr<u8>, n: ulong): io.IoResult<ulong> {
    var ssl = _tls_openssl.get();
    var read = ssl._ssl_read;
    var connection = _tls_session_ssl(session);
    var rc = read(connection, destination, _tls_chunk(n));
    if (rc > 0) {
        return io.IoResult<ulong>.ok(rc as ulong);
    }
    var get_error = ssl._ssl_error;
    var kind = get_error(connection, rc);
    if (kind == 6) {  # SSL_ERROR_ZERO_RETURN: the peer sent close_notify
        return io.IoResult<ulong>.ok(0);
    }
    if (kind == 5 && _tls_session_error(session)[0] == __null) {
        # SSL_ERROR_SYSCALL with no io error: the socket reached its end.
        var clear = ssl._error_clear;
        clear();
        return io.IoResult<ulong>.ok(0);
    }
    return io.IoResult<ulong>.err(_tls_session_failure(session, rc, "TLS read failed"));
}

# Encrypts and sends up to `n` bytes from `source`.
[Target(!OS(Windows))]
export _tls_sys_write(session: __ptr<void>, source: __ptr<u8>, n: ulong): io.IoResult<ulong> {
    if (n == 0) {
        return io.IoResult<ulong>.ok(0);
    }
    var write = _tls_openssl.get()._ssl_write;
    var rc = write(_tls_session_ssl(session), source, _tls_chunk(n));
    if (rc > 0) {
        return io.IoResult<ulong>.ok(rc as ulong);
    }
    return io.IoResult<ulong>.err(_tls_session_failure(session, rc, "TLS write failed"));
}

# Sends close_notify.
[Target(!OS(Windows))]
export _tls_sys_shutdown(session: __ptr<void>): io.IoResult<void> {
    var shutdown = _tls_openssl.get()._ssl_shutdown;
    var rc = shutdown(_tls_session_ssl(session));
    if (rc < 0) {
        return io.IoResult<void>.err(_tls_session_failure(session, rc, "TLS shutdown failed"));
    }
    return io.IoResult<void>.ok();
}

# Frees the SSL (and with it the BIO) and the block.
[Target(!OS(Windows))]
export _tls_sys_session_free(session: __ptr<void>) {
    var ssl_free = _tls_openssl.get()._ssl_free;
    ssl_free(_tls_session_ssl(session));
    _tls_session_error(session)[0] = __default<io.IoError>();
    _pep_free(session);
}

# SSL_read and SSL_write take an int count.
[Target(!OS(Windows))]
_tls_chunk(n: ulong): int {
    if (n > 1073741824) {
        return 1073741824;
    }
    return n as int;
}
