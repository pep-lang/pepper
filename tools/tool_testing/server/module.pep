## A file server on loopback for tests that download, standing in for
## GitHub's releases (`pep-install`) and its archives (`pep-package`). A
## module of its own, so tests that do not download are built without
## HTTP.

import async;
import http;
import io;
import [File, Path] from io;
import toolchain;

## Serves the files of the folder `root` over HTTP on 127.0.0.1, on a port
## the system picks, until `async.run` ends; call it inside `async.run`.
## The URL's path is the folder's own, since the handler, which runs on any
## worker, can capture nothing to say where it is. A file that is missing
## answers 404.
##
## @param root the folder to serve
## @returns the URL of that folder, ending in `/`
export serve_folder(root: Path): String {
    var server = http.Server.bind(io.SocketAddress(io.IpAddress.loopback_v4(), 0)).value();
    var port = server.local_address().value().port();
    async.spawn<void>(
        () => {
            server.serve(
                (request) => {
                    var path = request.path();
                    # `/C:/Users/...` on Windows.
                    var file = toolchain.is_windows() ? path.substr(1, path.length) : path;
                    var data = File.read_bytes(Path(file));
                    if (data.is_err()) {
                        return http.Response(404);
                    }
                    return http.Response(200).set_body(data.value());
                }
            );
        }
    );
    var folder = root.to_string().replace("\\", "/");
    return "http://127.0.0.1:" + to_string(port) + (folder.starts_with("/") ? "" : "/") + folder + "/";
}
