## HTTP/1.1 clients and servers, over TCP or TLS.
##
## Bring it in with `import http`. A `Client` sends a `Request` to an
## `http://` or `https://` URL and returns the `Response`; a `Server`
## accepts connections on every worker of `async.run` and answers each
## request with a handler function. Bodies are read into memory, or
## streamed through an `io.Reader` (`Client.open`, `set_reader`).
##
## - [Messages](http-message.md): `Headers`, `Request`, and `Response`
## - [Client](http-client.md): `Client` and `BodyReader`
## - [Server](http-server.md): `Server` and `reason_phrase`
##
## @example
##     import async;
##     import http;
##     import io;
##
##     main(): int {
##         async.run(() => {
##             var server = http.Server.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
##             var port = server.local_address().value().port();
##             async.spawn<void>(() => {
##                 server.serve((request) => {
##                     return http.Response(200).set_text("hello");
##                 });
##             });
##             var response = http.Client().get("http://127.0.0.1:" + to_string(port) + "/").value();
##             assert(response.text() == "hello", "served");
##         });
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "client";
import "message";
import "server";

export Headers;
export Request;
export Response;
export Client;
export MAX_RESPONSE_BODY;
export BodyReader;
export Server;
export MAX_REQUEST_BODY;
export reason_phrase;
