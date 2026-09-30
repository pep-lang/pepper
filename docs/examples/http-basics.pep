import async;
import http;
import io;

# Answers every request: `/hello` greets, anything else is not found.
handle(request: http.Request): http.Response {
    if (request.path() == "/hello") {
        var response = http.Response(200).set_text("hello, " + request.query());
        response.headers["Content-Type"] = "text/plain";
        return response;
    }
    return http.Response(404).set_text("nothing at " + request.path());
}

main(): int {
    async.run(
        () => {
            # Port 0 asks the system for any free port.
            var server = http.Server.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
            var port = server.local_address().value().port();
            # serve() runs until async.run ends, so it gets a task of its own.
            async.spawn<void>(() => {
                server.serve(handle);
            });

            var base = "http://127.0.0.1:" + to_string(port);
            var client = http.Client();
            var response = client.get(base + "/hello?pepper").value();
            assert(response.status == 200, "found");
            assert(response.text() == "hello, pepper", "the handler's text");
            assert(response.headers["content-type"] == "text/plain", "names ignore case");

            var missing = client.get(base + "/elsewhere").value();
            assert(missing.status == 404 && missing.reason == "Not Found", "not found");

            var posted = client.post(base + "/hello", "text/plain", "a body").value();
            assert(posted.is_success(), "any method reaches the handler");
        }
    );
    return 0;
}
