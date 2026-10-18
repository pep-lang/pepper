# io.Watcher: changes reported outside a task and in one (on the default
# backend and on poll), new subdirectories watched as they appear, a wait
# ended by a timeout, a cancel or a close, and the errors of open.

import async;
import io;
import [File, Directory, Path, Watcher, FileChange, ChangeKind] from io;

# Whether `changes` holds one of `kind` for `path`.
has_change(changes: FileChange[], kind: ChangeKind, path: Path): bool {
    for (var change in changes) {
        if (change.kind == kind && change.path.to_string() == path.to_string()) {
            return true;
        }
    }
    return false;
}

# Waits until `watcher` reports `kind` for `path`, giving up after five
# seconds; whether it came. Runs in a task.
waits_for(watcher: Watcher, kind: ChangeKind, path: Path): bool {
    with (async.timeout(5000)) {
        while (true) {
            var changes = watcher.wait();
            if (changes.is_err()) {
                return false;
            }
            if (has_change(changes.value(), kind, path)) {
                return true;
            }
        }
    }
    return false;
}

[Test]
open_fails_on_a_file_or_a_missing_path() {
    var folder = TempFolder("watch_open_fails");
    var file = folder.path.join("plain.txt");
    expect_true(File.write_text(file, "x").is_ok());
    var on_file = Watcher.open(file);
    expect_true(on_file.is_err() && on_file.error().is_not_a_directory());
    var missing = Watcher.open(folder.path.join("missing"));
    expect_true(missing.is_err() && missing.error().is_not_found());
}

[Test]
changes_made_before_a_wait_are_reported_outside_a_task() {
    var folder = TempFolder("watch_outside_a_task");
    var watcher = Watcher.open(folder.path).value();
    expect_true(watcher.is_open());
    var path = folder.path.join("notes.txt");
    expect_true(File.write_text(path, "one").is_ok());
    expect_true(has_change(watcher.wait().value(), ChangeKind.Created, path));
    expect_true(File.write_text(path, "two").is_ok());
    expect_true(has_change(watcher.wait().value(), ChangeKind.Modified, path));
    expect_true(File.remove(path).is_ok());
    expect_true(has_change(watcher.wait().value(), ChangeKind.Removed, path));
    watcher.close();
    expect_false(watcher.is_open());
    expect_true(watcher.wait().is_err());
    # Closing again does nothing.
    watcher.close();
}

[Test]
a_rename_reports_the_old_path_removed_and_the_new_one_created() {
    var folder = TempFolder("watch_rename");
    var before = folder.path.join("before.txt");
    var after = folder.path.join("after.txt");
    expect_true(File.write_text(before, "x").is_ok());
    async.run(() => {
        var watcher = Watcher.open(folder.path).value();
        expect_true(File.rename(before, after).is_ok());
        expect_true(waits_for(watcher, ChangeKind.Removed, before));
        expect_true(File.rename(after, before).is_ok());
        expect_true(waits_for(watcher, ChangeKind.Created, before));
    });
}

# Runs the task checks on `backend`.
changes_park_a_task_on(backend: async.Backend) {
    var folder = TempFolder("watch_in_a_task_" + backend.name());
    var root = folder.path;
    async.run_with(
        async.RuntimeOptions().backend(backend),
        () => {
            var watcher = Watcher.open(root).value();

            # A change made while the task is parked wakes it.
            var path = root.join("later.txt");
            var writer = async.Task<bool>.spawn_local(() => {
                async.sleep(20);
                return File.write_text(path, "x").is_ok();
            });
            expect_true(waits_for(watcher, ChangeKind.Created, path));
            expect_true(writer.join().value());

            # A new directory is watched, and what lands in it is reported.
            var sub = root.join("sub");
            expect_true(Directory.create(sub).is_ok());
            expect_true(waits_for(watcher, ChangeKind.Created, sub));
            var inner = sub.join("inner.txt");
            expect_true(File.write_text(inner, "x").is_ok());
            expect_true(waits_for(watcher, ChangeKind.Created, inner));

            # A directory where nothing happens, for the waits that end
            # another way.
            expect_true(Directory.create(root.join("quiet")).is_ok());
            var quiet = Watcher.open(root.join("quiet")).value();

            # The task's timeout ends the wait.
            with (async.timeout(30)) {
                var timed = quiet.wait();
                expect_true(timed.is_err() && timed.error().is_timed_out());
            }

            # Cancelling the task parked in the wait.
            var outcome = Array<bool>();
            var cancelled = async.Task<bool>.spawn_local(() => {
                var r = quiet.wait();
                outcome.append(r.is_err() && r.error().is_cancelled());
                return true;
            });
            async.sleep(10);
            cancelled.cancel();
            expect_true(cancelled.join().is_err());
            expect_equal(outcome.count, 1);
            expect_true(outcome[0]);

            # Closing the watcher ends a wait in another task.
            var closed = async.Task<bool>.spawn_local(() => {
                return quiet.wait().is_err();
            });
            async.sleep(10);
            quiet.close();
            expect_true(closed.join().value());
        }
    );
}

[Test]
changes_park_a_task_on_the_default_backend() {
    changes_park_a_task_on(async.Backend.Automatic);
}

[Test]
changes_park_a_task_on_poll() {
    changes_park_a_task_on(async.Backend.Poll);
}
