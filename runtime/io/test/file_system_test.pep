# Files and directories: writing and reading bytes and text, OpenOptions,
# seeking, set_length, metadata, whole-file locks, directories, copy, rename and remove, the
# error kinds each reports, a File closing its handle on last release, the
# io enums (ErrorKind, SeekFrom, FileType, StdStream), streaming a directory
# and a file's lines, and a File moved to another thread (FileTransfer).

import async;
import [
    File,
    OpenOptions,
    Directory,
    DirEntry,
    DirectoryIterator,
    Path,
    IoError,
    ErrorKind,
    SeekFrom,
    FileType,
    StdStream,
    Metadata
] from io;

[Target(OS(Windows))]
extern int GetHandleInformation(void* handle, void* flags);

text(path: Path): String {
    return File.read_to_string(path).value();
}

entry(list: DirEntry[], name: String): DirEntry {
    for (var e in list) {
        if (e.name == name) {
            return e;
        }
    }
    return DirEntry();
}

has_entry(list: DirEntry[], name: String): bool {
    return entry(list, name).name == name;
}

[Test]
temp_is_an_absolute_folder() {
    var temp = Directory.temp();
    expect_true(temp.is_absolute());
    expect_true(temp.is_dir());
}

[Test]
a_file_moves_to_another_thread() {
    var folder = TempFolder("a_file_moves_to_another_thread");
    var path = folder.path.join("moved.txt");
    expect_true(File.write_text(path, "carried over").is_ok());
    var file = File.open(path).value();
    var transfer = file.into_transfer();
    # The File it came from is closed; the handle travels with the token.
    expect_false(file.is_open());
    var read = async.Atomic<long>(-1);
    var reader = async.Thread.spawn(() => {
        var mine = File.adopt(transfer);
        if (mine.is_ok()) {
            var bytes = mine.value().read_all();
            read.store(bytes.is_ok() ? bytes.value().count as long : -2);
        }
    });
    reader.join();
    expect_equal(read.load(), 12);
    # A token gives its handle once.
    expect_true(File.adopt(transfer).is_err());
    expect_true(File.adopt(File().into_transfer()).is_err());
}

[Test]
bytes_and_text_round_trip() {
    var folder = TempFolder("bytes_and_text_round_trip");
    # Every byte value.
    var bin = folder.path.join("bytes.bin");
    var data = Array<u8>();
    int i = 0;
    while (i < 256) {
        data.append(i as u8);
        i = i + 1;
    }
    expect_true(File.write_bytes(bin, data).is_ok());
    var back = File.read_bytes(bin);
    expect_true(back.is_ok());
    expect_equal(back.value().count, 256);
    expect_true(back.value() == data);

    # Text, including non-ASCII.
    var t = folder.path.join("text.txt");
    expect_true(File.write_text(t, "hello, wörld").is_ok());
    expect_equal(text(t), "hello, wörld");
    expect_equal(t.metadata().value().size, 13);

    # Invalid UTF-8 is an invalid-input error.
    var bad = Array<u8>();
    bad.append(255);
    bad.append(254);
    var bad_file = folder.path.join("bad.txt");
    expect_true(File.write_bytes(bad_file, bad).is_ok());
    var r = File.read_to_string(bad_file);
    expect_true(r.is_err());
    expect_true(r.error().is_invalid_input());
}

[Test]
open_options_append_create_new_and_truncate() {
    var folder = TempFolder("open_options_append_create_new_and_truncate");
    var t = folder.path.join("text.txt");
    expect_true(File.write_text(t, "hello, wörld").is_ok());

    var a = OpenOptions().append(true).open(t);
    expect_true(a.is_ok());
    expect_true(a.value().write_all(" again").is_ok());
    expect_true(a.value().close().is_ok());
    expect_equal(text(t), "hello, wörld again");

    # create_new fails on an existing file, succeeds on a new one.
    var existing = OpenOptions().write(true).create_new(true).open(t);
    expect_true(existing.is_err());
    expect_true(existing.error().is_already_exists());
    expect_true(existing.error().message.size > 0);
    var fresh = folder.path.join("fresh.txt");
    var created = OpenOptions().write(true).create_new(true).open(fresh);
    expect_true(created.is_ok());
    expect_true(created.value().write_all("new".bytes()).is_ok());
    expect_true(created.value().close().is_ok());
    expect_equal(text(fresh), "new");

    # Open without create fails on a missing file.
    var missing = folder.path.join("missing.txt");
    var m = File.open(missing);
    expect_true(m.is_err());
    expect_true(m.error().is_not_found());
    expect_false(missing.exists());
    expect_true(OpenOptions().write(true).open(missing).error().is_not_found());
    expect_true(File.create(folder.path.join("no/such/dir.txt")).error().is_not_found());

    # Option validation.
    expect_true(OpenOptions().open(t).error().is_invalid_input());
    expect_true(OpenOptions().read(true).create(true).open(t).error().is_invalid_input());

    # Truncate.
    var truncated = OpenOptions().write(true).truncate(true).open(t);
    expect_true(truncated.is_ok());
    expect_equal(truncated.value().metadata().value().size, 0);
    truncated.value().close();
    expect_equal(text(t), "");
}

[Test]
a_lock_excludes_other_files_until_released() {
    var folder = TempFolder("a_lock_excludes_other_files_until_released");
    var path = folder.path.join("fetch.lock");
    var first = OpenOptions().write(true).create(true).open(path).value();
    var second = OpenOptions().write(true).create(true).open(path).value();

    # An exclusive lock keeps out every other lock, shared or exclusive.
    expect_true(first.lock().is_ok());
    expect_false(second.try_lock().value());
    expect_false(second.try_lock_shared().value());

    # Released, the other File takes it.
    expect_true(first.unlock().is_ok());
    expect_true(second.try_lock().value());
    expect_false(first.try_lock_shared().value());
    expect_true(second.unlock().is_ok());

    # Shared locks admit each other but not an exclusive one.
    expect_true(first.lock_shared().is_ok());
    expect_true(second.try_lock_shared().value());
    expect_false(OpenOptions().write(true).open(path).value().try_lock().value());
    expect_true(first.unlock().is_ok());
    expect_true(second.unlock().is_ok());

    # Unlocking a File that holds no lock is fine.
    expect_true(second.unlock().is_ok());

    # Closing a File releases its lock.
    expect_true(first.try_lock().value());
    expect_true(first.close().is_ok());
    expect_true(second.try_lock().value());
    expect_true(second.close().is_ok());

    # A closed File has nothing to lock.
    expect_true(first.lock().is_err());
    expect_true(first.try_lock().is_err());
    expect_true(first.unlock().is_err());
}

[Test]
seek_set_length_metadata_and_close() {
    var folder = TempFolder("seek_set_length_metadata_and_close");
    var p = folder.path.join("seek.txt");
    expect_true(File.write_text(p, "0123456789").is_ok());
    var o = OpenOptions().read(true).write(true).open(p);
    expect_true(o.is_ok());
    var f = o.value();
    expect_true(f.is_open());
    expect_equal(f.seek_end(0).value(), 10);
    expect_equal(f.seek_start(3).value(), 3);
    var buffer = Array<u8>();
    expect_equal(f.read(buffer, 2).value(), 2);
    expect_equal(buffer.count, 2);
    expect_equal(buffer[0], 51);
    expect_equal(buffer[1], 52);
    expect_equal(f.seek_current(2).value(), 7);
    expect_equal(f.read(buffer, 10).value(), 3);
    expect_equal(buffer.count, 5);
    expect_equal(buffer[2], 55);
    expect_equal(buffer[4], 57);
    expect_equal(f.read(buffer, 10).value(), 0);
    expect_equal(f.seek_current(-4).value(), 6);
    var before_start = f.seek_current(-100);
    expect_true(before_start.is_err());
    expect_true(before_start.error().is_invalid_input());
    expect_true(f.seek_start(0).is_ok());
    expect_true(f.write_all("AB").is_ok());
    expect_true(f.sync().is_ok());
    expect_equal(text(p), "AB23456789");

    # set_length shrinks and zero-extends, keeping the position.
    expect_true(f.set_length(4).is_ok());
    expect_equal(f.metadata().value().size, 4);
    expect_true(f.set_length(8).is_ok());
    expect_equal(f.seek_current(0).value(), 2);
    var all = File.read_bytes(p).value();
    expect_equal(all.count, 8);
    expect_equal(all[3], 51);
    expect_equal(all[4], 0);
    expect_equal(all[7], 0);

    # Metadata of an open file.
    var md = f.metadata().value();
    expect_true(md.is_file);
    expect_false(md.is_directory);
    expect_false(md.is_symlink);
    expect_true(md.modified > 0);
    expect_true(md.accessed > 0);
    expect_false(md.read_only);
    [Target(!OS(Windows))]
    {
        expect_true((md.permissions & 256) != 0);  # POSIX mode bits: owner can read
    }

    # Close is explicit and idempotent; a closed File refuses I/O.
    expect_true(f.close().is_ok());
    expect_false(f.is_open());
    expect_true(f.close().is_ok());
    expect_true(f.read(buffer, 1).is_err());
    expect_true(f.write_all("x").is_err());

    # A file opened only to append can still be synced.
    var appending = OpenOptions().append(true).open(p);
    expect_true(appending.is_ok());
    expect_true(appending.value().write_all("Z").is_ok());
    expect_true(appending.value().sync().is_ok());
    expect_true(appending.value().close().is_ok());
    expect_equal(File.read_bytes(p).value().count, 9);

    # A directory opens read-only but cannot be read.
    var directory = File.open(folder.path);
    expect_true(directory.is_ok());
    var read = directory.value().read_all();
    expect_true(read.is_err());
    expect_true(read.error().is_is_a_directory());
}

[Test]
create_list_and_remove_directories() {
    var folder = TempFolder("create_list_and_remove_directories");
    var base = folder.path;
    var nested = base.join("x").join("y").join("z");
    expect_true(Directory.create_all(nested).is_ok());
    expect_true(nested.is_dir());
    expect_false(nested.is_file());
    expect_true(nested.exists());
    expect_true(Directory.create_all(nested).is_ok());
    var again = Directory.create(nested);
    expect_true(again.is_err());
    expect_true(again.error().is_already_exists());
    expect_true(Directory.create(base.join("p/q")).error().is_not_found());

    var d = base.join("list");
    expect_true(Directory.create(d).is_ok());
    expect_true(File.write_text(d.join("a.txt"), "a").is_ok());
    expect_true(File.write_text(d.join("b.txt"), "bb").is_ok());
    expect_true(Directory.create(d.join("sub")).is_ok());

    # Listing an empty path fails as on POSIX, rather than listing the
    # current directory.
    var blank = Directory();
    blank.path = Path("");
    expect_true(blank.entries().error().is_not_found());
    var empty_dir = base.join("empty");
    expect_true(Directory.create(empty_dir).is_ok());
    expect_equal(Directory.open(empty_dir).value().entries().value().count, 0);
    expect_true(Directory.remove(empty_dir).is_ok());

    var opened = Directory.open(d);
    expect_true(opened.is_ok());
    var entries = opened.value().entries();
    expect_true(entries.is_ok());
    var list = entries.value();
    expect_equal(list.count, 3);
    expect_true(has_entry(list, "a.txt"));
    expect_true(has_entry(list, "b.txt"));
    expect_true(has_entry(list, "sub"));
    var sub = entry(list, "sub");
    expect_true(sub.is_directory);
    expect_false(sub.is_file);
    var b = entry(list, "b.txt");
    expect_true(b.is_file);
    expect_false(b.is_directory);
    expect_false(b.is_symlink);
    expect_true(b.path == d.join("b.txt"));
    expect_equal(b.metadata().value().size, 2);

    var not_directory = Directory.open(d.join("a.txt"));
    expect_true(not_directory.is_err());
    expect_true(not_directory.error().is_not_a_directory());
    expect_true(Directory.open(d.join("nope")).error().is_not_found());

    var not_empty = Directory.remove(d);
    expect_true(not_empty.is_err());
    expect_true(not_empty.error().is_directory_not_empty());
    expect_true(Directory.remove(d.join("sub")).is_ok());
    expect_false(d.join("sub").exists());
}

[Test]
copy_rename_and_remove_files() {
    var folder = TempFolder("copy_rename_and_remove_files");
    var d = folder.path;
    var a = d.join("a.txt");
    var c = d.join("c.txt");
    expect_true(File.write_text(a, "a").is_ok());
    expect_true(File.write_text(d.join("b.txt"), "bb").is_ok());
    expect_equal(File.copy(d.join("b.txt"), c).value(), 2);
    expect_equal(text(c), "bb");
    # Copying a file onto itself fails instead of truncating it first.
    expect_true(File.copy(c, c).error().is_invalid_input());
    expect_true(File.copy(c, d.join(".").join("c.txt")).error().is_invalid_input());
    expect_equal(text(c), "bb");
    var moved = d.join("moved.txt");
    expect_true(File.rename(c, moved).is_ok());
    expect_false(c.exists());
    expect_true(moved.exists());
    expect_true(File.rename(a, moved).is_ok());
    expect_equal(text(moved), "a");
    expect_true(File.remove(moved).is_ok());
    expect_false(moved.exists());
    var gone = File.remove(moved);
    expect_true(gone.is_err());
    expect_true(gone.error().is_not_found());
    expect_true(File.copy(moved, c).error().is_not_found());
}

[Test]
current_directory_and_canonicalize() {
    var folder = TempFolder("current_directory_and_canonicalize");
    var d = folder.path.join("list");
    expect_true(Directory.create(d).is_ok());
    expect_true(File.write_text(d.join("b.txt"), "bb").is_ok());
    var cwd = Directory.current();
    expect_true(cwd.is_ok());
    expect_true(cwd.value().is_absolute());
    expect_true(Directory.set_current(d).is_ok());
    var here = Directory.current().value().canonicalize().value();
    expect_true(here == d.canonicalize().value());
    expect_true(Path("b.txt").is_file());
    expect_true(Directory.set_current(cwd.value()).is_ok());
    var dotted = d.join("..").join("list").join("b.txt");
    expect_true(dotted.canonicalize().value() == d.join("b.txt").canonicalize().value());
    expect_true(d.join("none").canonicalize().error().is_not_found());
}

[Test]
remove_all_removes_a_tree_but_not_what_links_point_to() {
    var folder = TempFolder("remove_all_removes_a_tree_but_not_what_links_point_to");
    var base = folder.path;
    var tree = base.join("tree");
    expect_true(Directory.create_all(tree.join("inner").join("deep")).is_ok());
    expect_true(File.write_text(tree.join("inner").join("f.txt"), "f").is_ok());
    # A symlink inside it is removed, never what it points to. Not on
    # Windows, which needs a privilege for symlinks.
    var keep = base.join("keep");
    expect_true(Directory.create(keep).is_ok());
    expect_true(File.write_text(keep.join("k.txt"), "k").is_ok());
    [Target(!OS(Windows))]
    {
        var link = tree.join("link");
        expect_true(Directory.symlink(keep, link).is_ok());
        var link_metadata = link.symlink_metadata();
        expect_true(link_metadata.is_ok());
        expect_true(link_metadata.value().is_symlink);
        expect_true(link.metadata().value().is_directory);
        var listed = Directory.open(tree).value().entries().value();
        expect_true(entry(listed, "link").is_symlink);
    }
    expect_true(Directory.remove_all(tree).is_ok());
    expect_false(tree.exists());
    expect_true(keep.join("k.txt").is_file());
    expect_true(Directory.remove_all(base.join("absent")).error().is_not_found());
}

# set_permissions, set_read_only, set_executable, set_modified and
# set_accessed on Path and File, OpenOptions.mode, Directory.create with a
# mode, and symlinks made and read back.
[Test]
permissions_and_times() {
    var folder = TempFolder("permissions_and_times");
    var d = folder.path.join("perm");
    expect_true(Directory.create(d, mode = 448).is_ok());
    var f = d.join("run.sh");
    var file = OpenOptions().write(true).create_new(true).mode(448).open(f).value();
    expect_true(file.write_all("#!/bin/sh\n").is_ok());
    [Target(OS(Linux) || OS(Mac))]
    {
        expect_equal(d.metadata().value().permissions & 511, 448);
        expect_equal(file.metadata().value().permissions, 448);
        expect_true(file.set_permissions(420).is_ok());
        expect_equal(f.metadata().value().permissions, 420);
        expect_true(file.set_executable(true).is_ok());
        expect_equal(f.metadata().value().permissions, 493);
        expect_true(f.set_executable(false).is_ok());
        expect_equal(f.metadata().value().permissions, 420);
        expect_true(f.set_permissions(256).is_ok());
        # Executable only where readable.
        expect_true(f.set_executable(true).is_ok());
        expect_equal(f.metadata().value().permissions, 320);
        # Writable by the owner only.
        expect_true(f.set_read_only(false).is_ok());
        expect_equal(f.metadata().value().permissions, 448);
    }
    # Times are nanoseconds since the epoch; before 1970 too. Windows keeps
    # 100 ns.
    expect_true(file.set_modified(1000000000123456700).is_ok());
    expect_true(file.set_accessed(-1500000000).is_ok());
    var m = file.metadata().value();
    expect_equal(m.modified, 1000000000123456700);
    expect_equal(m.accessed, -1500000000);
    expect_true(file.close().is_ok());
    expect_true(f.set_accessed(2000000000).is_ok());
    expect_equal(f.metadata().value().accessed, 2000000000);
    expect_equal(f.metadata().value().modified, 1000000000123456700);
    expect_true(f.set_modified(3000000000).is_ok());
    expect_equal(f.metadata().value().modified, 3000000000);
    expect_equal(f.metadata().value().accessed, 2000000000);

    # Read-only, portably.
    expect_true(f.set_read_only(true).is_ok());
    expect_true(f.metadata().value().read_only);
    expect_true(_is_root() or OpenOptions().write(true).open(f).error().is_permission_denied());
    expect_true(f.set_read_only(false).is_ok());
    expect_false(f.metadata().value().read_only);
    expect_true(File.write_text(f, "again").is_ok());

    # A directory's time; set after its contents.
    expect_true(d.set_modified(4000000000).is_ok());
    expect_equal(d.metadata().value().modified, 4000000000);

    var missing = d.join("none");
    expect_true(missing.set_permissions(420).error().is_not_found());
    expect_true(missing.set_modified(0).error().is_not_found());
    expect_true(missing.set_read_only(true).error().is_not_found());
    expect_true(Path("").set_modified(0).error().is_not_found());
    expect_true(File().set_permissions(420).is_err());
    expect_true(File().set_modified(0).is_err());
    expect_true(f.read_link().error().is_invalid_input());

    [Target(!OS(Windows))]
    {
        var link = d.join("latest");
        expect_true(File.symlink(Path("run.sh"), link).is_ok());
        expect_true(link.read_link().value() == Path("run.sh"));
        expect_true(link.symlink_metadata().value().is_symlink);
        expect_equal(text(link), "again");
        expect_true(File.symlink(Path("x"), link).error().is_already_exists());
        var up = d.join("up");
        expect_true(Directory.symlink(Path(".."), up).is_ok());
        expect_true(up.join("perm").is_directory());
        var dangling = d.join("dangling");
        expect_true(File.symlink(Path("nowhere"), dangling).is_ok());
        expect_true(dangling.read_link().value() == Path("nowhere"));
        expect_true(d.join("none").read_link().error().is_not_found());
    }
}

# Root ignores permission bits, so a read-only file still opens for writing.
[Target(OS(Linux) || OS(Mac))]
extern uint geteuid();

[Target(OS(Linux) || OS(Mac))]
_is_root(): bool {
    return geteuid() == 0;
}

[Target(!(OS(Linux) || OS(Mac)))]
_is_root(): bool {
    return false;
}

[Test]
file_closes_on_last_release() {
    var folder = TempFolder("file_closes_on_last_release");
    var p = folder.path.join("x.txt");
    expect_true(File.write_text(p, "x").is_ok());
    [Target(!OS(Windows))]
    {
        # A dropped File's descriptor is the lowest free one again.
        var first = -1;
        {
            var f = File.open(p).value();
            first = f._handle;
        }
        var again = File.open(p).value();
        expect_equal(again._handle, first);
    }
    [Target(OS(Windows))]
    {
        # A dropped File's HANDLE is no longer valid. (The temporary File
        # is released at the end of the declaration.)
        var handle = File.open(p).value()._handle;
        var flags = _pep_malloc(4);
        expect_equal(GetHandleInformation(handle, flags), 0);
        _pep_free(flags);
    }
    # A loop of opens never runs out of handles.
    int i = 0;
    while (i < 3000) {
        expect_true(File.open(p).is_ok());
        i = i + 1;
    }
}

# Windows and macOS always report a creation time.
[Target(!OS(Linux))]
check_created(m: Metadata) {
    expect_true(m.created.is_value());
    expect_true(m.created.value() > 0);
}

# Linux reports one only when the file system records it.
[Target(OS(Linux))]
check_created(m: Metadata) {
    if (m.created) {
        expect_true(m.created.value() > 0);
    }
}

kind_name(e: IoError): String {
    return match (e.kind()) {
        NotFound => "not found",
        AlreadyExists => "exists",
        else => "other",
    };
}

[Test]
error_kind_agrees_with_the_predicates() {
    var folder = TempFolder("error_kind_agrees_with_the_predicates");
    var missing = File.open(folder.path.join("missing.txt"));
    expect_true(missing.is_err());
    expect_true(missing.error().kind() == ErrorKind.NotFound);
    expect_true(missing.error().is_not_found());
    expect_false(missing.error().is_permission_denied());
    expect_equal(kind_name(missing.error()), "not found");
    var again = Directory.create(folder.path);
    expect_true(again.error().kind() == ErrorKind.AlreadyExists);
    expect_true(again.error().is_already_exists());
    expect_equal(kind_name(again.error()), "exists");
    expect_true(IoError().kind() == ErrorKind.Other);
    expect_equal(ErrorKind.TimedOut.name(), "TimedOut");
}

[Test]
seek_from_start_current_and_end() {
    var folder = TempFolder("seek_from_start_current_and_end");
    var path = folder.path.join("data.bin");
    expect_true(File.write_text(path, "0123456789").is_ok());
    var f = File.open(path).value();
    expect_equal(f.seek(SeekFrom.End(0)).value(), 10);
    expect_equal(f.seek(SeekFrom.Start(4)).value(), 4);
    expect_equal(f.seek(SeekFrom.Current(-2)).value(), 2);
    expect_equal(f.seek(SeekFrom.End(-3)).value(), 7);
    var buffer = Array<u8>();
    expect_equal(f.read(buffer, 1).value(), 1);
    expect_equal(buffer[0], 55);
    expect_equal(f.seek(SeekFrom.Current(0)).value(), 8);
    expect_true(f.seek(SeekFrom.Start(-1)).is_err());
    f.close();
    expect_true(f.seek(SeekFrom.Start(0)).is_err());
}

[Test]
file_type_on_metadata_and_entries() {
    var folder = TempFolder("file_type_on_metadata_and_entries");
    var base = folder.path;
    var path = base.join("data.bin");
    expect_true(File.write_text(path, "0123456789").is_ok());
    var file_metadata = path.metadata().value();
    expect_true(file_metadata.file_type == FileType.File);
    expect_true(file_metadata.is_file);
    check_created(file_metadata);
    var directory_metadata = base.metadata().value();
    expect_true(directory_metadata.file_type == FileType.Directory);
    expect_true(directory_metadata.is_directory);
    check_created(directory_metadata);
    var opened = File.open(path).value();
    var open_metadata = opened.metadata().value();
    expect_true(open_metadata.file_type == FileType.File);
    expect_equal(open_metadata.created.is_value(), file_metadata.created.is_value());
    opened.close();
    expect_true(Metadata().file_type == FileType.Other);
    expect_true(Metadata().created.is_empty());
    expect_true(DirEntry().file_type == FileType.Other);

    expect_true(Directory.create(base.join("sub")).is_ok());
    var files = 0;
    var directories = 0;
    for (var e in Directory.open(base).value().entries().value()) {
        if (e.name == "data.bin") {
            expect_true(e.file_type == FileType.File);
            expect_true(e.is_file);
            files = files + 1;
        }
        if (e.name == "sub") {
            expect_true(e.file_type == FileType.Directory);
            expect_true(e.is_directory);
            directories = directories + 1;
        }
    }
    expect_equal(files, 1);
    expect_equal(directories, 1);
}

[Test]
std_file_takes_a_std_stream() {
    var error = File.std_file(StdStream.Error, "<err>");
    expect_true(error.is_open());
    expect_equal(error.path.to_string(), "<err>");
}

count_entries(directory: Directory): int {
    var n = 0;
    for (var e in directory) {
        expect_true(e.is_ok());
        n += 1;
    }
    return n;
}

first_name(directory: Directory): String {
    for (var e in directory) {
        return e.value().name;  # leaves the loop with the listing open
    }
    return "";
}

lines_of(text: String, path: Path): Array<String> {
    expect_true(File.write_text(path, text).is_ok());
    var f = File.open(path).value();
    var out = Array<String>();
    for (var line in f.lines()) {
        out.append(line.value());
    }
    return out;
}

[Test]
a_directory_streams_its_entries() {
    var folder = TempFolder("a_directory_streams_its_entries");
    var base = folder.path;
    var directory = Directory.open(base).value();

    # An empty directory yields nothing; then three entries, each once.
    expect_equal(count_entries(directory), 0);
    expect_true(File.write_text(base.join("a.txt"), "x").is_ok());
    expect_true(File.write_text(base.join("b.txt"), "y").is_ok());
    expect_true(Directory.create(base.join("sub")).is_ok());
    expect_equal(count_entries(directory), 3);
    var iterator = directory.iterate();
    var seen = 0;
    while (iterator.next()) {
        var e = iterator.current().value();
        expect_true(e.path == base.join(e.name));
        if (e.name == "sub") {
            expect_true(e.is_directory);
            expect_false(e.is_file);
            seen += 1;
        }
    }
    expect_equal(seen, 1);
    expect_false(iterator.next());
    expect_equal(directory.entries().value().count, 3);

    # Leaving early closes the listing: thousands of early exits do not run
    # out of handles.
    int i = 0;
    while (i < 3000) {
        expect_true(first_name(directory).size > 0);
        i += 1;
    }

    # A missing directory yields one error, then ends.
    var errors = 0;
    for (var e in DirectoryIterator(base.join("missing"))) {
        expect_true(e.is_err());
        expect_true(e.error().is_not_found());
        errors += 1;
    }
    expect_equal(errors, 1);
}

[Test]
a_file_streams_its_lines() {
    var folder = TempFolder("a_file_streams_its_lines");
    # Endings stripped, \r\n too, no empty line after a final ending.
    var p = folder.path.join("lines.txt");
    var lines = lines_of("one\r\ntwo\n\nlast", p);
    expect_equal(lines.count, 4);
    expect_equal(lines[0], "one");
    expect_equal(lines[1], "two");
    expect_equal(lines[2], "");
    expect_equal(lines[3], "last");
    expect_equal(lines_of("a\nb\n", p).count, 2);
    expect_equal(lines_of("", p).count, 0);
    var big = "";
    while (big.size < 200000) {
        big += "0123456789abcdef\n";
    }
    expect_equal(lines_of(big, p).count, big.size / 17);
    expect_true(File.write_bytes(p, [104 as u8, 255 as u8, 10 as u8]).is_ok());
    var f = File.open(p).value();
    var bad = f.lines().to_array();
    expect_equal(bad.count, 1);
    expect_true(bad[0].is_err());
    expect_true(bad[0].error().is_invalid_input());
}
