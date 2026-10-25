# The Security.framework layer for tls on iOS. Every declaration carries
# [Target(OS(IOS))]; openssl.pep, schannel.pep and wasi.pep declare the same
# `_tls_sys_*` functions for the other systems. It shares openssl.pep's
# session block (`_tls_session_ssl`, `_tls_session_error`), `_tls_error` and
# `_tls_symbol`, and schannel.pep's `_tls_pem_blocks`.
#
# iOS ships no OpenSSL. Secure Transport (SSLContext) is the platform's one
# TLS engine that runs over a socket the program already has, through I/O
# callbacks, as OpenSSL's BIO does: Network.framework opens its own
# connections, so it cannot take a `TcpStream`. Secure Transport is
# deprecated and speaks TLS 1.2 at most, but it is in every iOS SDK.
# Security.framework and CoreFoundation are opened at run time (dlopen), as
# libssl is elsewhere, so linking needs no `-framework`.
#
# The read and write callbacks call the io socket layer, which parks a task
# when the socket would block, so they never return errSSLWouldBlock. The
# handshake stops after the server's certificate arrives
# (kSSLSessionOptionBreakOnServerAuth) so that this layer checks it with
# SecTrust: the system's roots and those added with `add_root_certificate`,
# under the SSL policy for the host name or IP address.
#
# Only the client side is here: a server, or a client presenting a
# certificate, needs a SecIdentity, which iOS makes only from the keychain or
# a PKCS #12 file, so those return an error for now.
#
# A context is a malloc'd block of two words: the added roots (a
# CFMutableArray of SecCertificates, or null) and the ALPN protocols (a
# CFMutableArray of CFStrings, or null). A session is openssl.pep's block:
# the SSLContext, the socket, and the io error a callback met.

import async;
import io;
import "openssl";
import "schannel";
import "wasi";

# OSStatus values (SecureTransport.h).
const _TLS_ST_CLOSED_GRACEFUL: int = -9805;
const _TLS_ST_CLOSED_ABORT: int = -9806;
const _TLS_ST_CLOSED_NO_NOTIFY: int = -9816;
const _TLS_ST_PEER_AUTH_COMPLETED: int = -9841;
# kCFStringEncodingUTF8.
const _TLS_ST_UTF8: uint = 134217984;

# The Security.framework and CoreFoundation functions tls calls, or none when
# they could not be opened.
[Target(OS(IOS))]
[Shared]
struct _SecureTransport {
    # Whether both frameworks were opened; every other field is null
    # otherwise.
    const _loaded: bool;
    const _create_context: extern (__ptr<void>, int, int) => __ptr<void>;
    const _set_io: extern (__ptr<void>, __ptr<void>, __ptr<void>) => int;
    const _set_connection: extern (__ptr<void>, __ptr<void>) => int;
    const _set_peer_name: extern (__ptr<void>, __ptr<void>, ulong) => int;
    const _set_min_version: extern (__ptr<void>, int) => int;
    const _set_option: extern (__ptr<void>, int, u8) => int;
    const _set_alpn: extern (__ptr<void>, __ptr<void>) => int;
    const _copy_alpn: extern (__ptr<void>, __ptr<void>) => int;
    const _handshake: extern (__ptr<void>) => int;
    const _read: extern (__ptr<void>, __ptr<void>, ulong, __ptr<void>) => int;
    const _buffered: extern (__ptr<void>, __ptr<void>) => int;
    const _write: extern (__ptr<void>, __ptr<void>, ulong, __ptr<void>) => int;
    const _close: extern (__ptr<void>) => int;
    const _copy_peer_trust: extern (__ptr<void>, __ptr<void>) => int;
    const _trust_set_policies: extern (__ptr<void>, __ptr<void>) => int;
    const _trust_set_anchors: extern (__ptr<void>, __ptr<void>) => int;
    const _trust_set_anchors_only: extern (__ptr<void>, u8) => int;
    const _trust_evaluate: extern (__ptr<void>, __ptr<void>) => u8;
    const _policy_ssl: extern (u8, __ptr<void>) => __ptr<void>;
    const _certificate_create: extern (__ptr<void>, __ptr<void>) => __ptr<void>;
    const _status_message: extern (int, __ptr<void>) => __ptr<void>;
    const _release: extern (__ptr<void>) => void;
    const _array_create: extern (__ptr<void>, long, __ptr<void>) => __ptr<void>;
    const _array_append: extern (__ptr<void>, __ptr<void>) => void;
    const _array_count: extern (__ptr<void>) => long;
    const _array_at: extern (__ptr<void>, long) => __ptr<void>;
    const _string_create: extern (__ptr<void>, __ptr<void>, long, uint, u8) => __ptr<void>;
    const _string_bytes: extern (__ptr<void>, __ptr<void>, long, uint) => u8;
    const _data_create: extern (__ptr<void>, __ptr<void>, long) => __ptr<void>;
    const _error_description: extern (__ptr<void>) => __ptr<void>;
    # kCFTypeArrayCallBacks, the callbacks of an array of CF objects.
    const _array_callbacks: __ptr<void>;

    construct() {
        var security = dlopen("/System/Library/Frameworks/Security.framework/Security".c_str(), 2);  # RTLD_NOW
        var foundation = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation".c_str(), 2);
        _loaded = security != __null && foundation != __null;
        if (_loaded) {
            _create_context = _tls_symbol(
                security, "SSLCreateContext"
            ) as extern (__ptr<void>, int, int) => __ptr<void>;
            _set_io = _tls_symbol(security, "SSLSetIOFuncs") as extern (__ptr<void>, __ptr<void>, __ptr<void>) => int;
            _set_connection = _tls_symbol(security, "SSLSetConnection") as extern (__ptr<void>, __ptr<void>) => int;
            _set_peer_name = _tls_symbol(
                security, "SSLSetPeerDomainName"
            ) as extern (__ptr<void>, __ptr<void>, ulong) => int;
            _set_min_version = _tls_symbol(security, "SSLSetProtocolVersionMin") as extern (__ptr<void>, int) => int;
            _set_option = _tls_symbol(security, "SSLSetSessionOption") as extern (__ptr<void>, int, u8) => int;
            _set_alpn = _tls_symbol(security, "SSLSetALPNProtocols") as extern (__ptr<void>, __ptr<void>) => int;
            _copy_alpn = _tls_symbol(security, "SSLCopyALPNProtocols") as extern (__ptr<void>, __ptr<void>) => int;
            _handshake = _tls_symbol(security, "SSLHandshake") as extern (__ptr<void>) => int;
            _read = _tls_symbol(security, "SSLRead") as extern (__ptr<void>, __ptr<void>, ulong, __ptr<void>) => int;
            _buffered = _tls_symbol(security, "SSLGetBufferedReadSize") as extern (__ptr<void>, __ptr<void>) => int;
            _write = _tls_symbol(security, "SSLWrite") as extern (__ptr<void>, __ptr<void>, ulong, __ptr<void>) => int;
            _close = _tls_symbol(security, "SSLClose") as extern (__ptr<void>) => int;
            _copy_peer_trust = _tls_symbol(security, "SSLCopyPeerTrust") as extern (__ptr<void>, __ptr<void>) => int;
            _trust_set_policies = _tls_symbol(
                security, "SecTrustSetPolicies"
            ) as extern (__ptr<void>, __ptr<void>) => int;
            _trust_set_anchors = _tls_symbol(
                security, "SecTrustSetAnchorCertificates"
            ) as extern (__ptr<void>, __ptr<void>) => int;
            _trust_set_anchors_only = _tls_symbol(
                security, "SecTrustSetAnchorCertificatesOnly"
            ) as extern (__ptr<void>, u8) => int;
            _trust_evaluate = _tls_symbol(
                security, "SecTrustEvaluateWithError"
            ) as extern (__ptr<void>, __ptr<void>) => u8;
            _policy_ssl = _tls_symbol(security, "SecPolicyCreateSSL") as extern (u8, __ptr<void>) => __ptr<void>;
            _certificate_create = _tls_symbol(
                security, "SecCertificateCreateWithData"
            ) as extern (__ptr<void>, __ptr<void>) => __ptr<void>;
            _status_message = _tls_symbol(
                security, "SecCopyErrorMessageString"
            ) as extern (int, __ptr<void>) => __ptr<void>;
            _release = _tls_symbol(foundation, "CFRelease") as extern (__ptr<void>) => void;
            _array_create = _tls_symbol(
                foundation, "CFArrayCreateMutable"
            ) as extern (__ptr<void>, long, __ptr<void>) => __ptr<void>;
            _array_append = _tls_symbol(foundation, "CFArrayAppendValue") as extern (__ptr<void>, __ptr<void>) => void;
            _array_count = _tls_symbol(foundation, "CFArrayGetCount") as extern (__ptr<void>) => long;
            _array_at = _tls_symbol(foundation, "CFArrayGetValueAtIndex") as extern (__ptr<void>, long) => __ptr<void>;
            _string_create = _tls_symbol(
                foundation, "CFStringCreateWithBytes"
            ) as extern (__ptr<void>, __ptr<void>, long, uint, u8) => __ptr<void>;
            _string_bytes = _tls_symbol(
                foundation, "CFStringGetCString"
            ) as extern (__ptr<void>, __ptr<void>, long, uint) => u8;
            _data_create = _tls_symbol(
                foundation, "CFDataCreate"
            ) as extern (__ptr<void>, __ptr<void>, long) => __ptr<void>;
            _error_description = _tls_symbol(
                foundation, "CFErrorCopyDescription"
            ) as extern (__ptr<void>) => __ptr<void>;
            _array_callbacks = _tls_symbol(foundation, "kCFTypeArrayCallBacks");
        }
    }
}

[Target(OS(IOS))]
const _tls_secure_transport = async.Lazy<_SecureTransport>(() => {
    return _SecureTransport();
});

# ── CoreFoundation values ────────────────────────────────────────────────────

# `text` as a CFString (to release), or null.
[Target(OS(IOS))]
_tls_st_string(st: _SecureTransport, text: __ptr<u8>, size: ulong): __ptr<void> {
    var create = st._string_create;
    return create(__null, text, size as long, _TLS_ST_UTF8, 0);
}

# The text of a CFString (not released here); "" for null.
[Target(OS(IOS))]
_tls_st_text(st: _SecureTransport, value: __ptr<void>): String {
    if (value == __null) {
        return "";
    }
    var bytes = st._string_bytes;
    __ptr<char> buffer = _pep_malloc(1024);
    var text = "";
    if (bytes(value, buffer, 1024, _TLS_ST_UTF8) != 0) {
        text = String(buffer);
    }
    _pep_free(buffer);
    return text;
}

# Releases a CF object that may be null.
[Target(OS(IOS))]
_tls_st_release(st: _SecureTransport, value: __ptr<void>) {
    if (value != __null) {
        var release = st._release;
        release(value);
    }
}

# ── Errors ───────────────────────────────────────────────────────────────────

# `what`, then the system's words for `status`.
[Target(OS(IOS))]
_tls_st_status_error(what: String, status: int): io.IoError {
    var st = _tls_secure_transport.get();
    var message = st._status_message;
    var words = message(status, __null);
    var text = _tls_st_text(st, words);
    _tls_st_release(st, words);
    if (text.size == 0) {
        return _tls_error($"{what} (OSStatus {status})");
    }
    return _tls_error($"{what}: {text} (OSStatus {status})");
}

# Why a Secure Transport call on `session` that returned `status` failed: the
# io error a callback met, or the status.
[Target(OS(IOS))]
_tls_st_failure(session: __ptr<void>, status: int, what: String): io.IoError {
    var slot = _tls_session_error(session);
    if (slot[0] != __null) {
        var e = slot[0];
        slot[0] = __default<io.IoError>();
        return e;
    }
    return _tls_st_status_error(what, status);
}

# The error of what iOS does not do yet. ENOTSUP.
[Target(OS(IOS))]
_tls_st_unsupported(what: String): io.IoError {
    return io.IoError(45, $"{what} is not supported on iOS yet");
}

# ── Contexts ─────────────────────────────────────────────────────────────────

[Target(OS(IOS))]
_tls_sys_client_context(): io.IoResult<__ptr<void>> {
    if (!_tls_secure_transport.get()._loaded) {
        return io.IoResult<__ptr<void>>.err(_tls_error("cannot open Security.framework"));
    }
    __ptr<__ptr<void>> block = _pep_malloc(2 * sizeof<ulong>());
    block[0] = __null;
    block[1] = __null;
    return io.IoResult<__ptr<void>>.ok(block);
}

[Target(OS(IOS))]
_tls_sys_server_context(chain: io.Path, key: io.Path): io.IoResult<__ptr<void>> {
    return io.IoResult<__ptr<void>>.err(_tls_st_unsupported("a TLS server"));
}

[Target(OS(IOS))]
_tls_sys_set_identity(context: __ptr<void>, chain: io.Path, key: io.Path): io.IoResult<void> {
    return io.IoResult<void>.err(_tls_st_unsupported("a TLS client certificate"));
}

# No server context exists on iOS, so nothing calls it.
[Target(OS(IOS))]
_tls_sys_require_client_certificate(context: __ptr<void>, roots: io.Path): io.IoResult<void> {
    return io.IoResult<void>.err(_tls_st_unsupported("a TLS server"));
}

# Also trusts the PEM certificates in `path`.
[Target(OS(IOS))]
_tls_sys_add_root(context: __ptr<void>, path: io.Path): io.IoResult<void> {
    var text = io.File.read_to_string(path);
    if (text.is_err()) {
        return io.IoResult<void>.err(_tls_error($"cannot read the certificates '{path}': {text.error().message}"));
    }
    var certificates = _tls_pem_blocks(text.value(), "CERTIFICATE");
    if (certificates.count == 0) {
        return io.IoResult<void>.err(_tls_error($"cannot load the certificates in '{path}': none found"));
    }
    var st = _tls_secure_transport.get();
    __ptr<__ptr<void>> block = context;
    if (block[0] == __null) {
        var create = st._array_create;
        block[0] = create(__null, 0, st._array_callbacks);
    }
    for (var der in certificates) {
        var data_create = st._data_create;
        var data = data_create(__null, der._data, der._size as long);
        var certificate_create = st._certificate_create;
        var certificate = certificate_create(__null, data);
        _tls_st_release(st, data);
        if (certificate == __null) {
            return io.IoResult<void>.err(_tls_error($"cannot load the certificates in '{path}'"));
        }
        var append = st._array_append;
        append(block[0], certificate);
        _tls_st_release(st, certificate);
    }
    return io.IoResult<void>.ok();
}

# Sets the protocols a client offers through ALPN: `list` is in the wire
# format, each name after its length. A server context does not exist here.
[Target(OS(IOS))]
_tls_sys_set_protocols(context: __ptr<void>, list: u8[], server: bool): io.IoResult<void> {
    var st = _tls_secure_transport.get();
    __ptr<__ptr<void>> block = context;
    _tls_st_release(st, block[1]);
    var create = st._array_create;
    var protocols = create(__null, 0, st._array_callbacks);
    ulong index = 0;
    while (index < list.count) {
        var size = list[index] as ulong;
        var name = _tls_st_string(st, list._data + index + 1, size);
        var append = st._array_append;
        append(protocols, name);
        _tls_st_release(st, name);
        index += 1 + size;
    }
    block[1] = protocols;
    return io.IoResult<void>.ok();
}

# The protocol the handshake chose through ALPN, or "" for none.
[Target(OS(IOS))]
_tls_sys_protocol(session: __ptr<void>): String {
    var st = _tls_secure_transport.get();
    var copy = st._copy_alpn;
    __ptr<__ptr<void>> out = _pep_malloc(sizeof<ulong>());
    out[0] = __null;
    var name = "";
    if (copy(_tls_session_ssl(session), out) == 0 && out[0] != __null) {
        var count = st._array_count;
        if (count(out[0]) > 0) {
            var at = st._array_at;
            name = _tls_st_text(st, at(out[0], 0));
        }
    }
    _tls_st_release(st, out[0]);
    _pep_free(out);
    return name;
}

[Target(OS(IOS))]
_tls_sys_context_free(context: __ptr<void>) {
    var st = _tls_secure_transport.get();
    __ptr<__ptr<void>> block = context;
    _tls_st_release(st, block[0]);
    _tls_st_release(st, block[1]);
    _pep_free(context);
}

# ── Connections ──────────────────────────────────────────────────────────────

# SSLReadFunc: reads exactly `length[0]` bytes, or reports how many arrived
# before the end of the stream or an io error.
[Target(OS(IOS))]
_tls_st_read(connection: __ptr<void>, data: __ptr<void>, length: __ptr<ulong>): int {
    __ptr<ulong> block = connection;
    __ptr<u8> destination = data;
    var wanted = length[0];
    ulong done = 0;
    while (done < wanted) {
        var r = io._io_sys_socket_receive(block[1] as io.SocketHandle, destination + done, wanted - done);
        if (r.is_err()) {
            _tls_session_error(connection)[0] = r.error();
            length[0] = done;
            return _TLS_ST_CLOSED_ABORT;
        }
        if (r.value() == 0) {
            length[0] = done;
            return _TLS_ST_CLOSED_NO_NOTIFY;
        }
        done += r.value();
    }
    return 0;
}

# SSLWriteFunc: sends all `length[0]` bytes, or reports how many went before
# an io error.
[Target(OS(IOS))]
_tls_st_write(connection: __ptr<void>, data: __ptr<void>, length: __ptr<ulong>): int {
    __ptr<ulong> block = connection;
    __ptr<u8> source = data;
    var wanted = length[0];
    ulong done = 0;
    while (done < wanted) {
        var r = io._io_sys_socket_send(block[1] as io.SocketHandle, source + done, wanted - done);
        if (r.is_err() || r.value() == 0) {
            _tls_session_error(connection)[0] = r.is_err() ?
                r.error() :
                io.IoError(io._io_sys_code_write_zero(), "failed to write the whole buffer");
            length[0] = done;
            return _TLS_ST_CLOSED_ABORT;
        }
        done += r.value();
    }
    return 0;
}

# Checks the server's certificate, which the handshake stopped for, against
# the system's roots and `context`'s, for `host`.
[Target(OS(IOS))]
_tls_st_check_server(
    st: _SecureTransport, context: __ptr<void>, connection: __ptr<void>, host: String
): io.IoResult<void> {
    __ptr<__ptr<void>> out = _pep_malloc(sizeof<ulong>());
    out[0] = __null;
    var copy_trust = st._copy_peer_trust;
    if (copy_trust(connection, out) != 0 || out[0] == __null) {
        _pep_free(out);
        return io.IoResult<void>.err(_tls_error("certificate verify failed: the server sent no certificate"));
    }
    var trust = out[0];
    var name = _tls_st_string(st, unsafe_cast<__ptr<u8>>(host.c_str()), host.size);
    var policy_ssl = st._policy_ssl;
    var policy = policy_ssl(1, name);  # a server's certificate, for `host`
    var set_policies = st._trust_set_policies;
    set_policies(trust, policy);
    __ptr<__ptr<void>> block = context;
    if (block[0] != __null) {
        var set_anchors = st._trust_set_anchors;
        var set_anchors_only = st._trust_set_anchors_only;
        set_anchors(trust, block[0]);
        set_anchors_only(trust, 0);  # the system's roots as well
    }
    out[0] = __null;
    var evaluate = st._trust_evaluate;
    var trusted = evaluate(trust, out) != 0;
    var reason = "";
    if (!trusted && out[0] != __null) {
        var describe = st._error_description;
        var words = describe(out[0]);
        reason = _tls_st_text(st, words);
        _tls_st_release(st, words);
    }
    _tls_st_release(st, out[0]);
    _pep_free(out);
    _tls_st_release(st, policy);
    _tls_st_release(st, name);
    _tls_st_release(st, trust);
    if (!trusted) {
        return io.IoResult<void>.err(_tls_error($"certificate verify failed: {reason}"));
    }
    return io.IoResult<void>.ok();
}

# Runs the client handshake on socket `h`, checking that the certificate is
# for `host` (a name, or an IP address).
[Target(OS(IOS))]
_tls_sys_connect(context: __ptr<void>, h: io.SocketHandle, host: String): io.IoResult<__ptr<void>> {
    var st = _tls_secure_transport.get();
    var create = st._create_context;
    var connection = create(__null, 1, 0);  # kSSLClientSide, kSSLStreamType
    if (connection == __null) {
        return io.IoResult<__ptr<void>>.err(_tls_error("cannot create a TLS connection"));
    }
    __ptr<void> session = _pep_malloc(3 * sizeof<ulong>());
    __ptr<__ptr<void>> words = session;
    words[0] = connection;
    words[2] = __null;
    __ptr<ulong> numbers = session;
    numbers[1] = h as ulong;
    var set_io = st._set_io;
    var set_connection = st._set_connection;
    var set_min_version = st._set_min_version;
    var set_option = st._set_option;
    set_io(connection, __function_pointer(_tls_st_read), __function_pointer(_tls_st_write));
    set_connection(connection, session);
    set_min_version(connection, 8);  # kTLSProtocol12
    set_option(connection, 0, 1);    # kSSLSessionOptionBreakOnServerAuth
    if (io.IpAddress.parse(host).is_err()) {
        var set_peer_name = st._set_peer_name;
        set_peer_name(connection, host.c_str(), host.size);  # SNI
    }
    __ptr<__ptr<void>> block = context;
    if (block[1] != __null) {
        var set_alpn = st._set_alpn;
        set_alpn(connection, block[1]);
    }
    var handshake = st._handshake;
    var status = handshake(connection);
    if (status == _TLS_ST_PEER_AUTH_COMPLETED) {
        var checked = _tls_st_check_server(st, context, connection, host);
        if (checked.is_err()) {
            _tls_sys_session_free(session);
            return io.IoResult<__ptr<void>>.err(checked.error());
        }
        status = handshake(connection);
    }
    if (status != 0) {
        var e = _tls_st_failure(session, status, "TLS handshake failed");
        _tls_sys_session_free(session);
        return io.IoResult<__ptr<void>>.err(e);
    }
    return io.IoResult<__ptr<void>>.ok(session);
}

# No server context exists on iOS, so nothing calls it.
[Target(OS(IOS))]
_tls_sys_accept(context: __ptr<void>, h: io.SocketHandle): io.IoResult<__ptr<void>> {
    return io.IoResult<__ptr<void>>.err(_tls_st_unsupported("a TLS server"));
}

# Reads up to `n` decrypted bytes into `destination`; 0 at the end of the
# stream.
[Target(OS(IOS))]
_tls_sys_read(session: __ptr<void>, destination: __ptr<u8>, n: ulong): io.IoResult<ulong> {
    var st = _tls_secure_transport.get();
    var connection = _tls_session_ssl(session);
    __ptr<ulong> processed = _pep_malloc(sizeof<ulong>());
    # SSLRead reads another record after copying what it holds when that
    # falls short of `n`, and a read callback here waits for it: ask for no
    # more than it holds, so that a read never waits with data at hand.
    processed[0] = 0;
    var buffered = st._buffered;
    var limit = n;
    if (buffered(connection, processed) == 0 && processed[0] > 0 && processed[0] < n) {
        limit = processed[0];
    }
    var read = st._read;
    var status = 0;
    # A record with no application data (a TLS 1.2 renegotiation's) reads
    # nothing and succeeds; that is not the end of the stream.
    processed[0] = 0;
    while (status == 0 && processed[0] == 0) {
        status = read(connection, destination, limit, processed);
    }
    var count = processed[0];
    _pep_free(processed);
    if (count > 0) {
        return io.IoResult<ulong>.ok(count);
    }
    if (_tls_session_error(session)[0] == __null) {
        if (status == _TLS_ST_CLOSED_GRACEFUL || status == _TLS_ST_CLOSED_NO_NOTIFY) {
            return io.IoResult<ulong>.ok(0);
        }
    }
    return io.IoResult<ulong>.err(_tls_st_failure(session, status, "TLS read failed"));
}

# Encrypts and sends up to `n` bytes from `source`.
[Target(OS(IOS))]
_tls_sys_write(session: __ptr<void>, source: __ptr<u8>, n: ulong): io.IoResult<ulong> {
    if (n == 0) {
        return io.IoResult<ulong>.ok(0);
    }
    var write = _tls_secure_transport.get()._write;
    __ptr<ulong> processed = _pep_malloc(sizeof<ulong>());
    processed[0] = 0;
    var status = write(_tls_session_ssl(session), source, n, processed);
    var count = processed[0];
    _pep_free(processed);
    if (status == 0 || count > 0) {
        return io.IoResult<ulong>.ok(count);
    }
    return io.IoResult<ulong>.err(_tls_st_failure(session, status, "TLS write failed"));
}

# Sends close_notify.
[Target(OS(IOS))]
_tls_sys_shutdown(session: __ptr<void>): io.IoResult<void> {
    var close = _tls_secure_transport.get()._close;
    var status = close(_tls_session_ssl(session));
    if (status != 0) {
        return io.IoResult<void>.err(_tls_st_failure(session, status, "TLS shutdown failed"));
    }
    return io.IoResult<void>.ok();
}

# Releases the SSLContext and frees the block.
[Target(OS(IOS))]
_tls_sys_session_free(session: __ptr<void>) {
    _tls_st_release(_tls_secure_transport.get(), _tls_session_ssl(session));
    _tls_session_error(session)[0] = __default<io.IoError>();
    _pep_free(session);
}
