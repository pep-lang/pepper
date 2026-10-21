<!-- Generated from runtime/http/module.pep by `pep-doc reference`. Do not edit. -->

# The http module

HTTP/1.1 and HTTP/2 clients and servers, over TCP or TLS.

Bring it in with `import http`. A `Client` sends a `Request` to an
`http://` or `https://` URL and returns the `Response`; a `Server`
accepts connections on every worker of `async.run` and answers each
request with a handler function. Bodies are read into memory, or
streamed through an `io.Reader` (`Client.open`, `set_reader`). Over TLS
the client and server choose HTTP/2 through ALPN when both have it, with
the same `Request` and `Response` types.

- [Messages](http-message.md): `Headers`, `Request`, and `Response`
- [Client](http-client.md): `Client`, `Session` and `BodyReader`
- [Server](http-server.md): `Server`, `Connection` and `reason_phrase`

**Example**
```pepper
import async;
import http;
import io;

main(): int {
    async.run(() => {
        var server = http.Server.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
        var port = server.local_address().value().port();
        async.spawn<void>(() => {
            server.serve((request) => {
                return http.Response(200).set_text("hello");
            });
        });
        var response = http.Client().get("http://127.0.0.1:" + to_string(port) + "/").value();
        assert(response.text() == "hello", "served");
    });
    return 0;
}
```

Source: `runtime/http/module.pep`
