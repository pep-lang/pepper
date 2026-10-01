## TLS connections: `TlsConnector` opens client connections, `TlsAcceptor`
## accepts server connections, and `TlsStream` is one encrypted connection
## over a `TcpStream`.

# The public types call the `_tls_sys_*` layer (openssl.pep, schannel.pep),
# which works on raw pointers: a context and a session are the platform's
# objects.

import io;
import "openssl";
import "schannel";

## Opens TLS client connections, checking each server's certificate.
##
## A connector trusts the system's root certificates; `add_root_certificate`
## trusts more, such as a test certificate authority. Each `connect` runs
## the TLS handshake over a connected `TcpStream` and checks that the
## server's certificate is valid and issued for the host name given. Only
## TLS 1.2 and 1.3 are offered.
##
## A connector is `[Shared]`: make one and use it from every thread and
## task. Configure it (`add_root_certificate`) before the first `connect`.
##
## @example
##     import tls;
##
##     var connector = tls.TlsConnector.create().value();
##     var stream = connector.connect_host("localhost", 8443).value();
##     stream.write_all("ping");
## @see TlsStream
[Shared]
export struct TlsConnector {
    # The platform's client context (an SSL_CTX), or null for none.
    const _context: __ptr<void>;

    ## Wraps a platform context. Use `TlsConnector.create`.
    ##
    ## @param context the platform's client context, or null for none
    construct(context: __ptr<void>) {
        _context = context;
    }

    ## Frees the context when the last reference goes. Connections made
    ## with it stay open.
    destruct {
        if (_context != __null) {
            _tls_sys_context_free(_context);
        }
    }

    ## Creates a connector that trusts the system's root certificates.
    ##
    ## @returns the connector; an error when no TLS library is available (on
    ##   Linux and macOS, OpenSSL 3: `libssl.so.3`, or Homebrew's or
    ##   MacPorts' `libssl.3.dylib`)
    static create(): io.IoResult<TlsConnector> {
        var context = _tls_sys_client_context();
        if (context.is_err()) {
            return io.IoResult<TlsConnector>.err(context.error());
        }
        return io.IoResult<TlsConnector>.ok(TlsConnector(context.value()));
    }

    ## Also trusts the certificates in the PEM file at `path`, for servers
    ## whose certificates the system does not trust, such as a private or
    ## test certificate authority.
    ##
    ## @param path a file of one or more PEM certificates
    ## @returns an Ok result; an error when the file cannot be read or holds
    ##   no certificate
    add_root_certificate(path: io.Path): io.IoResult<void> {
        return _tls_sys_add_root(_context, path);
    }

    ## Runs the TLS handshake as the client over `stream` and checks the
    ## server's certificate.
    ##
    ## @param stream a connected TCP stream; the `TlsStream` keeps it, and
    ##   nothing else should read or write it afterwards
    ## @param host the name the certificate must be for, also sent to the
    ##   server as the requested name (SNI); an IP address is checked against
    ##   the certificate's addresses instead
    ## @returns the encrypted stream; an error when the handshake fails or
    ##   the certificate is not trusted ("certificate verify failed: ..."), or
    ##   an io error from the socket
    connect(stream: io.TcpStream, host: String): io.IoResult<TlsStream> {
        if (!stream.is_open()) {
            return io.IoResult<TlsStream>.err(_tls_error("the TCP stream is closed"));
        }
        var session = _tls_sys_connect(_context, stream._handle, host);
        if (session.is_err()) {
            return io.IoResult<TlsStream>.err(session.error());
        }
        return io.IoResult<TlsStream>.ok(TlsStream(stream, session.value()));
    }

    ## Connects to `host` on `port` with `TcpStream.connect_host`, then runs
    ## the handshake as `connect` does.
    ##
    ## @param host a host name or an IP address
    ## @param port the port, usually 443
    ## @returns the encrypted stream; the errors of `TcpStream.connect_host`
    ##   and of `connect`
    connect_host(host: String, port: u16): io.IoResult<TlsStream> {
        var tcp = io.TcpStream.connect_host(host, port);
        if (tcp.is_err()) {
            return io.IoResult<TlsStream>.err(tcp.error());
        }
        return connect(tcp.value(), host);
    }
}

## Accepts TLS server connections with one certificate.
##
## An acceptor presents a certificate chain and its private key, read from
## PEM files. Each `accept` runs the TLS handshake over a `TcpStream` that a
## `TcpListener` accepted. Clients are not asked for certificates.
##
## An acceptor is `[Shared]`, so the accept loops of every worker can share
## one.
##
## @example
##     import io;
##     import tls;
##
##     var acceptor = tls.TlsAcceptor.create(io.Path("cert.pem"), io.Path("key.pem")).value();
##     var listener = io.TcpListener.bind(io.SocketAddress.parse("0.0.0.0:8443").value()).value();
##     while (true) {
##         var (tcp, peer) = listener.accept().value();
##         var accepted = acceptor.accept(tcp);
##         if (accepted.is_ok()) {
##             accepted.value().write_all("hello over TLS");
##         }
##     }
## @see TlsStream
[Shared]
export struct TlsAcceptor {
    # The platform's server context (an SSL_CTX), or null for none.
    const _context: __ptr<void>;

    ## Wraps a platform context. Use `TlsAcceptor.create`.
    ##
    ## @param context the platform's server context, or null for none
    construct(context: __ptr<void>) {
        _context = context;
    }

    ## Frees the context when the last reference goes.
    destruct {
        if (_context != __null) {
            _tls_sys_context_free(_context);
        }
    }

    ## Creates an acceptor that presents the certificate chain in
    ## `certificate_chain` with the private key in `private_key`.
    ##
    ## @param certificate_chain a PEM file: the server's certificate first,
    ##   then any intermediate certificates
    ## @param private_key a PEM file with the certificate's private key (on
    ##   Windows, PKCS #8: `BEGIN PRIVATE KEY`)
    ## @returns the acceptor; an error when a file cannot be read, the key
    ##   does not match the certificate, or no TLS library is available (see
    ##   `TlsConnector.create`)
    static create(certificate_chain: io.Path, private_key: io.Path): io.IoResult<TlsAcceptor> {
        var context = _tls_sys_server_context(certificate_chain, private_key);
        if (context.is_err()) {
            return io.IoResult<TlsAcceptor>.err(context.error());
        }
        return io.IoResult<TlsAcceptor>.ok(TlsAcceptor(context.value()));
    }

    ## Runs the TLS handshake as the server over `stream`.
    ##
    ## @param stream a connection a `TcpListener` accepted; the `TlsStream`
    ##   keeps it, and nothing else should read or write it afterwards
    ## @returns the encrypted stream; an error when the handshake fails, or
    ##   an io error from the socket
    accept(stream: io.TcpStream): io.IoResult<TlsStream> {
        if (!stream.is_open()) {
            return io.IoResult<TlsStream>.err(_tls_error("the TCP stream is closed"));
        }
        var session = _tls_sys_accept(_context, stream._handle);
        if (session.is_err()) {
            return io.IoResult<TlsStream>.err(session.error());
        }
        return io.IoResult<TlsStream>.ok(TlsStream(stream, session.value()));
    }
}

## An encrypted connection: TLS over a `TcpStream`.
##
## Get one from `TlsConnector.connect` or `TlsAcceptor.accept`. Reading and
## writing work as on a `TcpStream`, on the decrypted bytes: `read` appends
## what has arrived and returns 0 once the peer has closed the connection,
## `write` may send part of the data, and `read_exact` and `write_all` loop
## until done. In a task, a call that has to wait parks only the task.
##
## `shutdown()` tells the peer that nothing more is coming (a TLS
## close_notify). A peer that closes the TCP connection without one also
## ends the stream: `read` returns 0.
##
## Closing: the destructor closes the connection when the last reference
## goes; `close()` closes it earlier. Neither sends close_notify; call
## `shutdown()` first for that.
##
## @example
##     var stream = connector.connect_host("localhost", 8443).value();
##     stream.write_all("ping");
##     var reply = Array<u8>();
##     while (stream.read(reply, 4096).value() > 0) {
##     }
## @see TlsConnector
## @see TlsAcceptor
[NotCopyable("owns a TLS connection and cannot be copied")]
export struct TlsStream {
    # The TCP connection under the TLS one.
    io.TcpStream _tcp;
    # The platform's session (an SSL*, with its socket), or null once closed.
    __ptr<void> _session;

    ## Wraps a finished handshake. Use `TlsConnector.connect` or
    ## `TlsAcceptor.accept`.
    ##
    ## @param tcp the TCP connection
    ## @param session the platform's session, or null for a closed stream
    construct(tcp: io.TcpStream, session: __ptr<void>) {
        _tcp = tcp;
        _session = session;
    }

    ## Frees the session and closes the TCP connection when the last
    ## reference goes.
    destruct {
        if (_session != __null) {
            _tls_sys_session_free(_session);
        }
    }

    ## Returns whether the stream is open.
    ##
    ## @returns false after `close()`
    is_open(): bool {
        return _session != __null;
    }

    _check_open(): io.IoResult<void> {
        if (_session == __null) {
            return io.IoResult<void>.err(_tls_error("the TLS stream is closed"));
        }
        return io.IoResult<void>.ok();
    }

    ## Waits until data arrives, then appends up to `max` decrypted bytes of
    ## it to `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read; 0 reads nothing and returns 0
    ## @returns the number of bytes appended, 0 once the peer has closed the
    ##   connection; an error when the stream is closed, a TLS error, or an io
    ##   error from the socket
    read(buffer: u8[], max: ulong): io.IoResult<ulong> {
        var c = _check_open();
        if (c.is_err()) {
            return io.IoResult<ulong>.err(c.error());
        }
        if (max == 0) {
            return io.IoResult<ulong>.ok(0);
        }
        buffer.reserve(buffer._size + max);
        var r = _tls_sys_read(_session, buffer._data + buffer._size, max);
        if (r.is_ok()) {
            buffer._size = buffer._size + r.value();
        }
        return r;
    }

    ## Reads until exactly `count` more bytes are appended to `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param count the number of bytes to read
    ## @returns an Ok result once `count` bytes are appended; an error when
    ##   the connection ends first, or an error as for `read`. The bytes read
    ##   before an error stay in `buffer`.
    read_exact(buffer: u8[], count: ulong): io.IoResult<void> {
        ulong done = 0;
        while (done < count) {
            var r = read(buffer, count - done);
            if (r.is_err()) {
                return io.IoResult<void>.err(r.error());
            }
            if (r.value() == 0) {
                return io.IoResult<void>.err(_tls_error("the connection closed before every byte arrived"));
            }
            done = done + r.value();
        }
        return io.IoResult<void>.ok();
    }

    ## Encrypts and sends bytes from `data`. The send may be partial; use
    ## `write_all` to send everything.
    ##
    ## @param data the bytes to send
    ## @returns the number of bytes sent; an error when the stream is
    ##   closed, a TLS error, or an io error from the socket
    write(data: u8[]): io.IoResult<ulong> {
        var c = _check_open();
        if (c.is_err()) {
            return io.IoResult<ulong>.err(c.error());
        }
        return _tls_sys_write(_session, data._data, data._size);
    }

    ## Sends all of `data`, repeating the send until every byte is sent.
    ##
    ## @param data the bytes to send
    ## @returns an Ok result once every byte is sent; an error as for `write`
    write_all(data: u8[]): io.IoResult<void> {
        # Pinned so no other task can grow `data` while a send waits.
        data._pins = data._pins + 1;
        var r = _write_all(data._data, data._size);
        data._pins = data._pins - 1;
        return r;
    }

    ## Sends all of the UTF-8 bytes of `text`, as `write_all(u8[])` does.
    ## No newline or terminator is added.
    ##
    ## @param text the text to send
    ## @returns an Ok result once every byte is sent; an error as for `write`
    ## @example
    ##     stream.write_all("ping");
    write_all(text: String): io.IoResult<void> {
        if (!io._io_in_task()) {
            return _write_all(text.c_str() as __ptr<u8>, text.size());
        }
        # Another task could change `text` while a send waits, so send a
        # copy, as `io.File.write_all` does.
        var bytes = io._io_text_copy(text);
        var r = _write_all(bytes, text.size());
        _pep_free(bytes);
        return r;
    }

    ## Deprecated: use `write_all` instead. Sends all of the UTF-8 bytes of
    ## `text`, exactly like `write_all(text)`.
    ##
    ## @param text the text to send
    ## @returns an Ok result once every byte is sent; an error as for `write_all`
    ## @see write_all
    [Deprecated("use 'write_all' instead", "write_all")]
    write_string(text: String): io.IoResult<void> {
        return write_all(text);
    }

    _write_all(p: __ptr<u8>, n: ulong): io.IoResult<void> {
        var c = _check_open();
        if (c.is_err()) {
            return c;
        }
        ulong done = 0;
        while (done < n) {
            var r = _tls_sys_write(_session, p + done, n - done);
            if (r.is_err()) {
                return io.IoResult<void>.err(r.error());
            }
            if (r.value() == 0) {
                return io.IoResult<void>.err(
                    io.IoError(io._io_sys_code_write_zero(), "failed to write the whole buffer")
                );
            }
            done = done + r.value();
        }
        return io.IoResult<void>.ok();
    }

    ## Tells the peer that nothing more is coming (sends a TLS
    ## close_notify). The peer's reads return 0 after the data sent before.
    ##
    ## @returns an Ok result on success; an error when the stream is closed,
    ##   or an io error from the socket
    shutdown(): io.IoResult<void> {
        var c = _check_open();
        if (c.is_err()) {
            return c;
        }
        return _tls_sys_shutdown(_session);
    }

    ## Closes the connection now, without a close_notify (see `shutdown`).
    ## Closing a closed stream does nothing.
    ##
    ## @returns an Ok result on success or when already closed; the platform
    ##   error when closing the socket fails
    close(): io.IoResult<void> {
        if (_session == __null) {
            return io.IoResult<void>.ok();
        }
        _tls_sys_session_free(_session);
        _session = __null;
        return _tcp.close();
    }
}

extend TlsStream with io.Reader;

extend TlsStream with io.Writer;
