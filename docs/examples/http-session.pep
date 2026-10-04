import async;
import http;
import io;

main(): int {
    async.run(
        () => {
            var server = http.Server.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
            var port = server.local_address().value().port();
            async.spawn<void>(() => {
                server.serve((request) => {
                    return http.Response(200).set_text("page " + request.query());
                });
            });
            var base = "http://127.0.0.1:" + to_string(port);

            var session = http.Client().session();
            for (var page in 1..>3) {
                var response = session.get(base + "/items?" + to_string(page)).value();
                assert(response.text() == "page " + to_string(page), "each page");
            }
            # One connection carried all three requests, and waits for more.
            assert(session.idle_count == 1, "kept open");
            session.close();
        }
    );
    return 0;
}
