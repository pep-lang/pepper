import async;
import http;
import io;

# `/download` streams a body of unknown length, which goes out chunked;
# `/upload` reports how many bytes it received.
handle(request: http.Request): http.Response {
    if (request.path() == "/download") {
        var data = "pepper\n".repeat(100000).bytes();
        return http.Response(200).set_reader(io.ByteReader(data));
    }
    return http.Response(200).set_text(to_string(request.body().count));
}

main(): int {
    async.run(
        () => {
            var server = http.Server.bind(io.SocketAddress.parse("127.0.0.1:0").value()).value();
            var port = server.local_address().value().port();
            async.spawn<void>(() => {
                server.serve(handle);
            });
            var base = "http://127.0.0.1:" + to_string(port);
            var client = http.Client();

            # open() returns at the header fields; the body is read as it
            # arrives and written to a file a chunk at a time.
            var response = client.open(http.Request("GET", base + "/download")).value();
            assert(response.headers["transfer-encoding"] == "chunked", "no length up front");
            var path = io.Directory.temp().join("pepper-download.txt");
            var file = io.File.create(path).value();
            for (var chunk in response.reader().chunks(65536)) {
                file.write_all(chunk.value());
            }
            file.close();

            # Send the file back as a request body read from the file.
            var upload = http.Request("PUT", base + "/upload").set_reader(io.File.open(path).value());
            assert(client.send(upload).value().text() == "700000", "every byte arrived");
            io.File.remove(path);
        }
    );
    return 0;
}
