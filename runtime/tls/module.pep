## Encrypted connections: TLS 1.2 and 1.3 over TCP, for clients and servers.
##
## Bring it in with `import tls`. A `TlsConnector` opens client connections
## and checks each server's certificate; a `TlsAcceptor` accepts connections
## with a certificate and key from PEM files; a `TlsStream` reads and writes
## like an `io.TcpStream`. In a task, a call that has to wait parks only the
## task.
##
## On Linux and macOS the module uses OpenSSL 3, loaded when the first
## connector or acceptor is made; on Windows it uses SChannel.
##
## - [Streams](tls-stream.md): `TlsConnector`, `TlsAcceptor`, and `TlsStream`
##
## @example
##     import tls;
##
##     main(): int {
##         var connector = tls.TlsConnector.create().value();
##         var stream = connector.connect_host("localhost", 8443).value();
##         stream.write_all("ping");
##         var reply = Array<u8>();
##         while (stream.read(reply, 4096).value() > 0) {
##         }
##         return 0;
##     }

# This file only gathers the module's public API from its other files. The
# platform layer (`_tls_sys_*` in openssl.pep / schannel.pep) is exported
# between the tls files but not from the module.

import "stream";

export TlsConnector;
export TlsAcceptor;
export TlsStream;
