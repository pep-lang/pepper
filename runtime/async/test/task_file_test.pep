# File reads and writes in tasks, on each I/O backend, and growing an array
# that a read in a task is filling.

import async;
import io;
import [has_io_uring] from "backends";

private const ticks = async.Atomic<long>(0);

# Writes `size` patterned bytes to `path`, reads them back in 64 KiB reads,
# and checks them. Returns how many reads it took.
round_trip(path: io.Path, size: ulong): long {
    var data = Array<u8>();
    var i: ulong = 0;
    while (i < size) {
        data.append((i % 251) as u8);
        i = i + 1;
    }
    var out = io.File.create(path).value();
    # Write_all.
    expect_true(out.write_all(data).is_ok());
    # Write_all string.
    expect_true(out.write_all("tail").is_ok());
    out.close();
    var file = io.File.open(path).value();
    var back = Array<u8>();
    var reads: long = 0;
    while (true) {
        var r = file.read(back, 65536);
        # Read.
        expect_true(r.is_ok());
        if (r.value() == 0) {
            break;
        }
        reads = reads + 1;
    }
    file.close();
    # Every byte came back.
    expect_equal(back.count, size + 4);
    i = 0;
    while (i < size) {
        # The bytes match.
        expect_equal(back[i], (i % 251) as u8);
        i = i + 1;
    }
    # The string came last.
    expect_equal(back[size], 116);
    expect_equal(back[size + 3], 108);
    return reads;
}

files_park_their_task_on(backend: async.Backend, folder_name: String) {
    var folder = TempFolder(folder_name);
    var path = folder.path.join("round_trip.bin");
    async.run_with(
        async.RuntimeOptions().workers(1).backend(backend),
        () => {
            var stop = async.Atomic<int>(0);
            var ticker = async.Task<void>.spawn_local(() => {
                while (stop.load() == 0) {
                    ticks.fetch_add(1);
                    async.yield_now();
                }
            });
            var reads = round_trip(path, 1048576);
            # Read in chunks, and the worker ran another task during each read.
            expect_true(reads >= 16);
            expect_true(ticks.load() >= reads);

            # Errors come back as errors.
            var missing = io.File.open(folder.path.join("missing.bin"));
            expect_true(missing.is_err());
            expect_true(missing.error().is_not_found());

            # Several tasks at once.
            var tasks = Array<async.Task<long>>();
            ulong n = 0;
            while (n < 4) {
                var p = folder.path.join($"file-{n}.bin");
                tasks.append(async.Task<long>.spawn_local(() => {
                    return round_trip(p, 200000);
                }));
                n = n + 1;
            }
            for (var t in tasks) {
                # Each task read its file.
                expect_true(t.join().value() >= 4);
            }
            stop.store(1);
            ticker.join();
        }
    );
}

# File reads and writes in tasks: the task waits while the worker runs
# others, on the pool or (Linux) io_uring; results match.
[Test]
files_park_their_task() {
    files_park_their_task_on(async.Backend.Automatic, "files_park_their_task");
}

[Test]
files_park_their_task_with_poll() {
    files_park_their_task_on(async.Backend.Poll, "files_park_their_task_with_poll");
}

[Test]
files_park_their_task_with_io_uring() {
    if (has_io_uring()) {
        files_park_their_task_on(async.Backend.IoUring, "files_park_their_task_with_io_uring");
    }
}

# Growing an array that a file read in a task is filling panics.
[Test]
[ShouldPanic("Array: the buffer is in use by an I/O operation")]
growing_a_pinned_array_panics() {
    var folder = TempFolder("growing_a_pinned_array_panics");
    var path = folder.path.join("pinned.bin");
    io.File.write_text(path, "some bytes");
    async.run_with(async.RuntimeOptions().workers(1), () => {
        var buffer = Array<u8>();
        var file = io.File.open(path).value();
        var reader = async.Task<void>.spawn_local(() => {
            file.read(buffer, 64);
        });
        async.yield_now();
        buffer.reserve(buffer.capacity + 1);
        reader.join();
    });
}
