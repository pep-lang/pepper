# Watch a directory tree for changes with io.Watcher, inside a task.
import async;
import io;

main(): int {
    var folder = io.Directory.temp().join("pepper-files-watch-example");
    io.Directory.remove_all(folder);
    io.Directory.create_all(folder).value();
    var watcher = io.Watcher.open(folder).value();
    async.run(
        () => {
            var path = folder.join("hello.txt");
            io.File.write_text(path, "hi").value();
            # In a task the wait parks only the task, and a timeout ends it.
            with (async.timeout(5000)) {
                var changes = watcher.wait().value();
                for (var change in changes) {
                    if (change.kind == io.ChangeKind.Created && change.path.to_string() == path.to_string()) {
                        print($"created {change.path.file_name().value()}");
                    }
                }
            }
        }
    );
    watcher.close();
    io.Directory.remove_all(folder).value();
    return 0;
}
