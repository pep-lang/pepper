//! The `io` runtime module (`runtime/io/`): programs that `import io` (or
//! import names from it) are compiled, linked and run on the host. Each Pepper
//! program asserts internally — a failed `assert` prints its message and
//! aborts — and returns 0 on success; the harness reports the program's
//! output on failure.
//!
//! The programs are platform-aware (`[Target]` blocks) and run on every CI
//! host. In addition, `other_platforms_compile` pushes all of them through the
//! platform filter, sema and LLVM codegen with the host simulated as every
//! other platform, so each platform's code type-checks and produces valid IR
//! wherever the tests run; and `path_functions_on_every_platform` runs the
//! (pure) path program by JIT under each simulated platform's path rules.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use std::path::PathBuf;
use std::process::Command;

use crate::support;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

pub(crate) fn source_dir(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("pepper_io_{}_{}", name, std::process::id()))
}

/// Write `source` as `main.pep` in a fresh directory for `name`; return its
/// path and the directory.
fn write_source(name: &str, source: &str) -> (PathBuf, PathBuf) {
    let dir = source_dir(name);
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let src = dir.join("main.pep");
    std::fs::write(&src, source).unwrap();
    (src, dir)
}

/// Compile + link `source` into a native binary; return its path.
pub(crate) fn build(name: &str, source: &str) -> Result<PathBuf, String> {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let (src, dir) = write_source(name, source);
    let out = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src.to_string_lossy().into_owned(),
        "-o".to_string(),
        out.to_string_lossy().into_owned(),
        "--build".to_string(),
        dir.join("build").to_string_lossy().into_owned(),
    ]);
    let code = pepper_driver::run(options)?;
    assert_eq!(code, 0);
    Ok(out)
}

/// Build and run `source`; return (exit code, stdout, stderr).
fn run(name: &str, source: &str) -> (i32, String, String) {
    let exe = build(name, source).unwrap_or_else(|e| panic!("{name}: compile failed: {e}"));
    let output = Command::new(&exe).output().expect("spawn");
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    (output.status.code().unwrap_or(-1), stdout, stderr)
}

pub(crate) fn assert_runs(name: &str, source: &str) -> String {
    let (code, stdout, stderr) = run(name, source);
    // A failed assert prints its message (the second argument of the
    // assert) as the last line of stdout, then aborts.
    let failed = stdout.lines().last().unwrap_or("");
    assert_eq!(
        code, 0,
        "{name} exited with {code}; failed assert: {failed:?}\nstdout:\n{stdout}\nstderr:\n{stderr}"
    );
    // Keep a failing program's directory for inspection; drop a passing one.
    let _ = std::fs::remove_dir_all(source_dir(name));
    stdout
}

/// A scratch directory name for one test program, unique per test run.
fn scratch_name(test: &str) -> String {
    format!("pepper_io_scratch_{}_{}", test, std::process::id())
}

const PATH_PROGRAM: &str = r##"
import io;

s(p: io.Path): String { return p.to_string(); }

# The expected text of a path the implementation builds: `/` written here is
# the platform separator, `\` on Windows. (String literals have no escapes.)
w(text: String): String {
    var out = text.clone();
    [Target(OS(Windows))] {
        var p = out.c_str() as __ptr<u8>;
        ulong i = 0;
        while (i < out.size()) {
            if (p[i] == 47) {
                p[i] = 92;
            }
            i = i + 1;
        }
    }
    return out;
}

main(): int {
    # join / join_str: an absolute right-hand side replaces; separators are
    # not doubled; empty sides are neutral. Joining inserts the platform
    # separator; the rest is the input's text as written.
    assert(io.Path("a").join(io.Path("b")).to_string() == w("a/b"), "join");
    assert(io.Path("a/").join(io.Path("b")).to_string() == "a/b", "join after separator");
    assert(io.Path("a").join(io.Path("/abs")).to_string() == "/abs", "join absolute");
    assert(io.Path("").join(io.Path("b")).to_string() == "b", "join onto empty");
    assert(io.Path("a").join(io.Path("")).to_string() == "a", "join empty");
    assert(io.Path("usr").join("lib").join("x.so").to_string() == w("usr/lib/x.so"), "join a String");
    assert(io.Path("usr").join_str("lib").to_string() == w("usr/lib"), "deprecated join_str");

    # parent
    assert(io.Path("/a/b/c.txt").parent().to_string() == "/a/b", "parent");
    assert(io.Path("/a").parent().to_string() == "/", "parent of top-level");
    assert(io.Path("/").parent().to_string() == "", "parent of root");
    assert(io.Path("a").parent().to_string() == "", "parent of bare name");
    assert(io.Path("a/b/").parent().to_string() == "a", "parent ignores trailing separator");
    assert(io.Path("a//b").parent().to_string() == "a", "parent collapses separators");
    assert(io.Path("").parent().to_string() == "", "parent of empty");

    # file_name / file_stem / extension
    assert(io.Path("/a/b/c.txt").file_name() == "c.txt", "file_name");
    assert(io.Path("a/b/").file_name() == "b", "file_name trailing separator");
    assert(io.Path("/").file_name() == "", "file_name of root");
    assert(io.Path("a/..").file_name() == "", "file_name of ..");
    assert(io.Path("").file_name() == "", "file_name of empty");
    assert(io.Path("c.tar.gz").file_stem() == "c.tar", "file_stem");
    assert(io.Path("c.tar.gz").extension() == "gz", "extension");
    assert(io.Path("/x/.bashrc").file_stem() == ".bashrc", "dotfile stem");
    assert(io.Path("/x/.bashrc").extension() == "", "dotfile has no extension");
    assert(io.Path("foo.").file_stem() == "foo", "trailing dot stem");
    assert(io.Path("foo.").extension() == "", "trailing dot extension");
    assert(io.Path("a.b/c").extension() == "", "dot in a directory name");
    assert(io.Path("noext").file_stem() == "noext", "no extension stem");

    # with_extension
    assert(io.Path("a/b.txt").with_extension("md").to_string() == "a/b.md", "replace extension");
    assert(io.Path("a/b").with_extension("rs").to_string() == "a/b.rs", "add extension");
    assert(io.Path("a/b.txt").with_extension("").to_string() == "a/b", "remove extension");
    assert(io.Path(".bashrc").with_extension("x").to_string() == ".bashrc.x", "dotfile extension");
    assert(io.Path("/").with_extension("x").to_string() == "/", "no file name: unchanged");

    # components
    var c = io.Path("/usr//lib/./x/").components();
    assert(c.count() == 4, "components count");
    assert(c[0] == "/" && c[1] == "usr" && c[2] == "lib" && c[3] == "x", "components");
    var d = io.Path("./a/b").components();
    assert(d.count() == 3 && d[0] == "." && d[1] == "a" && d[2] == "b", "leading . kept");
    var e = io.Path("a/../b").components();
    assert(e.count() == 3 && e[1] == "..", ".. kept");
    assert(io.Path("").components().count() == 0, "no components");

    # normalize: rebuilt with the platform separator.
    assert(io.Path("a/./b/../c").normalize().to_string() == w("a/c"), "normalize");
    assert(io.Path("/../x").normalize().to_string() == w("/x"), ".. stops at the root");
    assert(io.Path("../a/..").normalize().to_string() == "..", "leading .. kept");
    assert(io.Path("a/..").normalize().to_string() == ".", "cleans to .");
    assert(io.Path("a//b/").normalize().to_string() == w("a/b"), "separators collapse");
    assert(io.Path("./").normalize().to_string() == ".", "./");
    assert(io.Path("").normalize().to_string() == "", "empty stays empty");

    # relative / empty / equality
    assert(!io.Path("x").is_absolute() && io.Path("x").is_relative(), "relative");
    assert(!io.Path("").is_absolute(), "empty is not absolute");
    assert(io.Path("").is_empty() && !io.Path("a").is_empty(), "is_empty");
    assert(io.Path.separator() == w("/"), "separator");
    assert(io.Path("a/b") == io.Path("a/b"), "==");
    assert(io.Path("a/b") != io.Path("a/c"), "!=");
    assert(io.Path("q").to_string() == "q", "to_string");
    assert(s(io.Path("z")) == "z", "Path as a parameter type");

    [Target(!OS(Windows))] {
        # POSIX: a root makes a path absolute; `\` is an ordinary byte.
        assert(io.Path("/x").is_absolute(), "absolute");
        assert(io.Path("//a//b/").normalize().to_string() == "/a/b", "leading separators collapse");
        assert(io.Path("a\\b").file_name() == "a\\b", "backslash is not a separator");
    }
    [Target(OS(Windows))] {
        # Windows: `\` and `/` both separate; absolute needs a drive and a
        # root, or a UNC `\\server\share` prefix.
        assert(!io.Path("/x").is_absolute(), "a root without a drive is relative");
        assert(!io.Path("C:x").is_absolute(), "a drive without a root is relative");
        assert(io.Path("C:/x").is_absolute() && io.Path(w("C:/x")).is_absolute(), "drive and root");
        assert(io.Path(w("//server/share/x")).is_absolute(), "UNC");
        assert(io.Path(w("a/b/c.txt")).parent().to_string() == w("a/b"), "parent with backslashes");
        assert(io.Path(w("a/b/c.txt")).file_name() == "c.txt", "file_name with backslashes");
        assert(io.Path("C:/a//./b/").normalize().to_string() == w("C:/a/b"), "normalize keeps the drive");
        assert(io.Path("C:/x").parent().to_string() == "C:/", "parent of a top-level name keeps the root");
        assert(io.Path("C:/").parent().to_string() == "", "parent of a drive root");
        var wc = io.Path(w("C:/a/b")).components();
        assert(wc.count() == 4 && wc[0] == "C:" && wc[1] == w("/") && wc[2] == "a" && wc[3] == "b", "drive components");
        assert(io.Path("a").join("C:/x").to_string() == "C:/x", "join a drive path replaces");
        assert(io.Path(w("C:/a")).join("b").to_string() == w("C:/a/b"), "join under a drive");
    }
    return 0;
}
"##;

#[test]
fn path_functions() {
    assert_runs("path", PATH_PROGRAM);
}

/// Everything that touches the file system, in one program: create, write
/// and read (bytes and text), OpenOptions, seek, set_len, metadata,
/// directories, copy/rename/remove, error kinds, and no leaked buffers.
fn fs_program(scratch: &str) -> String {
    r##"
import [File, OpenOptions, Directory, DirEntry, Path, IoError, IoResult, Metadata] from io;

[Target(!OS(Windows))] extern int symlink(char* target, char* link);

text(f: Path): String {
    return File.read_to_string(f).value();
}

bytes_of(s: String): u8[] {
    var out = Array<u8>();
    var p = s.c_str() as __ptr<u8>;
    ulong i = 0;
    while (i < s.size()) {
        out.append(p[i]);
        i = i + 1;
    }
    return out;
}

has_entry(list: DirEntry[], name: String): bool {
    ulong i = 0;
    while (i < list.count()) {
        if (list[i].name == name) {
            return true;
        }
        i = i + 1;
    }
    return false;
}

entry(list: DirEntry[], name: String): DirEntry {
    ulong i = 0;
    while (i < list.count()) {
        if (list[i].name == name) {
            return list[i];
        }
        i = i + 1;
    }
    return DirEntry();
}

files_and_text(base: Path) {
    # Bytes round trip: every byte value.
    var bin = base.join("bytes.bin");
    var data = Array<u8>();
    int i = 0;
    while (i < 256) {
        data.append(i as u8);
        i = i + 1;
    }
    assert(File.write_bytes(bin, data).is_ok(), "write_bytes");
    var back = File.read_bytes(bin);
    assert(back.is_ok(), "read_bytes");
    assert(back.value().count() == 256, "read_bytes size");
    assert(back.value() == data, "read_bytes content");

    # Text round trip, including non-ASCII.
    var t = base.join("text.txt");
    assert(File.write_text(t, "hello, wörld").is_ok(), "write_text");
    assert(text(t) == "hello, wörld", "read_to_string");
    assert(t.metadata().value().size == 13, "text size in bytes");

    # Invalid UTF-8 is an invalid-input error.
    var bad = Array<u8>();
    bad.append(255);
    bad.append(254);
    var badf = base.join("bad.txt");
    assert(File.write_bytes(badf, bad).is_ok(), "write invalid utf-8");
    var r = File.read_to_string(badf);
    assert(r.is_err(), "invalid utf-8 rejected");
    assert(r.error().is_invalid_input(), "invalid utf-8 rejected");

    # Append.
    var a = OpenOptions().append(true).open(t);
    assert(a.is_ok(), "open for append");
    assert(a.value().write_all(" again").is_ok(), "append write");
    assert(a.value().close().is_ok(), "close appended");
    assert(text(t) == "hello, wörld again", "appended");

    # create_new fails on an existing file, succeeds on a new one.
    var cn = OpenOptions().write(true).create_new(true).open(t);
    assert(cn.is_err(), "create_new on existing");
    assert(cn.error().is_already_exists(), "create_new on existing");
    assert(cn.error().message.size() > 0, "error message");
    var fresh = base.join("fresh.txt");
    var cn2 = OpenOptions().write(true).create_new(true).open(fresh);
    assert(cn2.is_ok(), "create_new on missing");
    assert(cn2.value().write_all(bytes_of("new")).is_ok(), "write_all");
    assert(cn2.value().close().is_ok(), "close new");
    assert(text(fresh) == "new", "create_new content");

    # Open without create fails on a missing file.
    var missing = base.join("missing.txt");
    var m = File.open(missing);
    assert(m.is_err(), "open missing: not found");
    assert(m.error().is_not_found(), "open missing: not found");
    assert(!missing.exists(), "missing does not exist");
    var nw = OpenOptions().write(true).open(missing);
    assert(nw.error().is_not_found(), "write without create: not found");
    var nodir = File.create(base.join("no/such/dir.txt"));
    assert(nodir.error().is_not_found(), "create under missing directory");

    # Option validation.
    assert(OpenOptions().open(t).error().is_invalid_input(), "no access mode");
    assert(OpenOptions().read(true).create(true).open(t).error().is_invalid_input(), "create needs write");

    # Truncate.
    var tr = OpenOptions().write(true).truncate(true).open(t);
    assert(tr.is_ok(), "open truncate");
    assert(tr.value().metadata().value().size == 0, "truncated size");
    tr.value().close();
    assert(text(t) == "", "truncated content");
}

seeking(base: Path) {
    var p = base.join("seek.txt");
    assert(File.write_text(p, "0123456789").is_ok(), "write seek file");
    var o = OpenOptions().read(true).write(true).open(p);
    assert(o.is_ok(), "open read+write");
    var f = o.value();
    assert(f.is_open(), "is_open");
    assert(f.seek_end(0).value() == 10, "seek_end");
    assert(f.seek_start(3).value() == 3, "seek_start");
    var buf = Array<u8>();
    assert(f.read(buf, 2).value() == 2, "read 2");
    assert(buf.count() == 2 && buf[0] == 51 && buf[1] == 52, "read at 3");
    assert(f.seek_current(2).value() == 7, "seek_current");
    assert(f.read(buf, 10).value() == 3, "read to end");
    assert(buf.count() == 5 && buf[2] == 55 && buf[4] == 57, "read appends");
    assert(f.read(buf, 10).value() == 0, "EOF");
    assert(f.seek_current(-4).value() == 6, "seek back");
    var before_start = f.seek_current(-100);
    assert(before_start.is_err(), "seek before the start");
    assert(before_start.error().is_invalid_input(), "seek before the start is invalid input");
    assert(f.seek_start(0).is_ok(), "rewind");
    assert(f.write_all("AB").is_ok(), "overwrite");
    assert(f.sync().is_ok(), "sync");
    assert(text(p) == "AB23456789", "overwritten");

    # set_len shrinks and zero-extends, keeping the position.
    assert(f.set_length(4).is_ok(), "set_length shrink");
    assert(f.metadata().value().size == 4, "shrunk");
    assert(f.set_length(8).is_ok(), "set_length grow");
    assert(f.seek_current(0).value() == 2, "position kept");
    var all = File.read_bytes(p).value();
    assert(all.count() == 8 && all[3] == 51 && all[4] == 0 && all[7] == 0, "zero-extended");

    # Metadata of an open file.
    var md = f.metadata().value();
    assert(md.is_file && !md.is_directory && !md.is_symlink, "file kind");
    assert(md.modified > 0 && md.accessed > 0, "timestamps");
    assert(!md.read_only, "writable");
    [Target(!OS(Windows))] {
        assert((md.permissions & 256) != 0, "owner can read");   # POSIX mode bits
    }

    # Close is explicit and idempotent; a closed File refuses I/O.
    assert(f.close().is_ok(), "close");
    assert(!f.is_open(), "closed");
    assert(f.close().is_ok(), "close again");
    assert(f.read(buf, 1).is_err(), "read after close");
    assert(f.write_all("x").is_err(), "write after close");

    # A file opened only to append can still be synced.
    var ap = OpenOptions().append(true).open(p);
    assert(ap.is_ok(), "open to append");
    assert(ap.value().write_all("Z").is_ok(), "append");
    assert(ap.value().sync().is_ok(), "sync in append mode");
    assert(ap.value().close().is_ok(), "close append");
    assert(File.read_bytes(p).value().count() == 9, "appended");

    # A directory opens read-only but cannot be read.
    var dr = File.open(base);
    assert(dr.is_ok(), "open directory");
    var rd = dr.value().read_all();
    assert(rd.is_err(), "read directory");
    assert(rd.error().is_is_a_directory(), "read directory");
}

directories(base: Path) {
    var nested = base.join("x").join("y").join("z");
    assert(Directory.create_all(nested).is_ok(), "create_all");
    assert(nested.is_dir() && !nested.is_file() && nested.exists(), "nested exists");
    assert(Directory.create_all(nested).is_ok(), "create_all again");
    var again = Directory.create(nested);
    assert(again.is_err(), "create existing");
    assert(again.error().is_already_exists(), "create existing");
    var nop = Directory.create(base.join("p/q"));
    assert(nop.error().is_not_found(), "create without parent");

    var d = base.join("list");
    assert(Directory.create(d).is_ok(), "create");
    assert(File.write_text(d.join("a.txt"), "a").is_ok(), "a.txt");
    assert(File.write_text(d.join("b.txt"), "bb").is_ok(), "b.txt");
    assert(Directory.create(d.join("sub")).is_ok(), "sub");

    # Listing an empty path fails as on POSIX, rather than listing the
    # current directory.
    var blank = Directory();
    blank.path = Path("");
    assert(blank.entries().error().is_not_found(), "list an empty path");
    var empty_dir = base.join("empty");
    assert(Directory.create(empty_dir).is_ok(), "create empty");
    assert(Directory.open(empty_dir).value().entries().value().count() == 0, "list an empty directory");
    assert(Directory.remove(empty_dir).is_ok(), "remove empty");

    var opened = Directory.open(d);
    assert(opened.is_ok(), "Directory.open");
    var entries = opened.value().entries();
    assert(entries.is_ok(), "entries");
    var list = entries.value();
    assert(list.count() == 3, "three entries");
    assert(has_entry(list, "a.txt") && has_entry(list, "b.txt") && has_entry(list, "sub"), "entry names");
    var sub = entry(list, "sub");
    assert(sub.is_directory && !sub.is_file, "sub is a directory");
    var b = entry(list, "b.txt");
    assert(b.is_file && !b.is_directory && !b.is_symlink, "b is a file");
    assert(b.path == d.join("b.txt"), "entry path");
    assert(b.metadata().value().size == 2, "entry metadata");

    var nd = Directory.open(d.join("a.txt"));
    assert(nd.is_err(), "open a file as a directory");
    assert(nd.error().is_not_a_directory(), "open a file as a directory");
    assert(Directory.open(d.join("nope")).error().is_not_found(), "open missing directory");

    var ne = Directory.remove(d);
    assert(ne.is_err(), "remove non-empty");
    assert(ne.error().is_directory_not_empty(), "remove non-empty");
    assert(Directory.remove(d.join("sub")).is_ok(), "remove empty");
    assert(!d.join("sub").exists(), "removed");

    # copy / rename / remove
    var a = d.join("a.txt");
    var c = d.join("c.txt");
    assert(File.copy(d.join("b.txt"), c).value() == 2, "copy count");
    assert(text(c) == "bb", "copied content");
    # Copying a file onto itself fails instead of truncating it first.
    assert(File.copy(c, c).error().is_invalid_input(), "copy onto itself");
    assert(File.copy(c, d.join(".").join("c.txt")).error().is_invalid_input(), "copy onto itself, other spelling");
    assert(text(c) == "bb", "self-copy kept content");
    var moved = d.join("moved.txt");
    assert(File.rename(c, moved).is_ok(), "rename");
    assert(!c.exists() && moved.exists(), "renamed");
    assert(File.rename(a, moved).is_ok(), "rename replaces");
    assert(text(moved) == "a", "replaced content");
    assert(File.remove(moved).is_ok(), "remove");
    assert(!moved.exists(), "removed file");
    var gone = File.remove(moved);
    assert(gone.is_err(), "remove missing");
    assert(gone.error().is_not_found(), "remove missing");
    assert(File.copy(moved, c).error().is_not_found(), "copy missing");

    # current directory and canonicalize
    var cwd = Directory.current();
    assert(cwd.is_ok(), "current");
    assert(cwd.value().is_absolute(), "current");
    assert(Directory.set_current(d).is_ok(), "set_current");
    var here = Directory.current().value().canonicalize().value();
    assert(here == d.canonicalize().value(), "now in d");
    assert(Path("b.txt").is_file(), "relative to the new current directory");
    assert(Directory.set_current(cwd.value()).is_ok(), "restore current");
    var dotted = d.join("..").join("list").join("b.txt");
    assert(dotted.canonicalize().value() == d.join("b.txt").canonicalize().value(), "canonicalize");
    assert(d.join("none").canonicalize().error().is_not_found(), "canonicalize missing");

    # remove_all removes a tree.
    var tree = base.join("tree");
    assert(Directory.create_all(tree.join("inner").join("deep")).is_ok(), "tree");
    assert(File.write_text(tree.join("inner").join("f.txt"), "f").is_ok(), "tree file");
    # A symlink inside it is removed, never what it points to. The link is
    # made with POSIX `symlink` (Windows needs a privilege for symlinks).
    var keep = base.join("keep");
    assert(Directory.create(keep).is_ok(), "keep");
    assert(File.write_text(keep.join("k.txt"), "k").is_ok(), "k.txt");
    [Target(!OS(Windows))] {
        var link = tree.join("link");
        assert(symlink(keep.to_string().c_str(), link.to_string().c_str()) == 0, "symlink");
        var lm = link.symlink_metadata();
        assert(lm.is_ok(), "symlink_metadata");
        assert(lm.value().is_symlink, "symlink_metadata");
        assert(link.metadata().value().is_directory, "metadata follows the link");
        var tl = Directory.open(tree).value().entries().value();
        assert(entry(tl, "link").is_symlink, "entry is a symlink");
    }
    assert(Directory.remove_all(tree).is_ok(), "remove_all");
    assert(!tree.exists(), "tree removed");
    assert(keep.join("k.txt").is_file(), "link target kept");
    assert(Directory.remove_all(base.join("absent")).error().is_not_found(), "remove_all missing");
}

run_all(scratch: String): int {
    var tmp = Directory.temp();
    assert(tmp.is_absolute() && tmp.is_dir(), "temp");
    var base = tmp.join(scratch);
    Directory.remove_all(base);
    assert(Directory.create(base).is_ok(), "create base");
    files_and_text(base);
    seeking(base);
    directories(base);
    assert(Directory.remove_all(base).is_ok(), "remove base");
    assert(!base.exists(), "base removed");
    return 0;
}

main(): int {
    var before = _pep_live_allocs();
    var rc = run_all("SCRATCH");
    var after = _pep_live_allocs();
    assert(after == before, "leaked allocations");
    print("io-fs-ok");
    return rc;
}
"##
    .replace("SCRATCH", scratch)
}

#[test]
fn file_system_round_trips() {
    let scratch = scratch_name("fs");
    let out = assert_runs("fs", &fs_program(&scratch));
    assert!(out.contains("io-fs-ok"), "output: {out}");
    assert!(!std::env::temp_dir().join(&scratch).exists(), "scratch directory left behind");
}

/// A File's destructor closes its handle, and a loop of opens never runs out
/// of handles.
fn close_program(scratch: &str) -> String {
    r##"
import [File, Path, Directory] from io;

[Target(OS(Windows))] extern int GetHandleInformation(void* handle, void* flags);

churn(p: Path) {
    [Target(!OS(Windows))] {
        # A dropped File's descriptor is the lowest free one again.
        var first = -1;
        {
            var f = File.open(p).value();
            first = f._handle;
        }
        var again = File.open(p).value();
        assert(again._handle == first, "descriptor not closed by the destructor");
    }
    [Target(OS(Windows))] {
        # A dropped File's HANDLE is no longer valid. (The temporary File
        # is released at the end of the declaration.)
        var h = File.open(p).value()._handle;
        var flags = _pep_malloc(4);
        assert(GetHandleInformation(h, flags) == 0, "handle not closed by the destructor");
        _pep_free(flags);
    }
    int i = 0;
    while (i < 3000) {
        var f = File.open(p);
        assert(f.is_ok(), "open (handle leak?)");
        i = i + 1;
    }
}

main(): int {
    var p = Directory.temp().join("SCRATCH.txt");
    assert(File.write_text(p, "x").is_ok(), "write");
    var before = _pep_live_allocs();
    churn(p);
    assert(_pep_live_allocs() == before, "leak");
    assert(File.remove(p).is_ok(), "remove");
    return 0;
}
"##
    .replace("SCRATCH", scratch)
}

const STDOUT_PROGRAM: &str = r##"
import io;

main(): int {
    var out = io.File.stdout();
    assert(out.is_open(), "stdout open");
    assert(out.write_all("io-stdout-ok").is_ok(), "write stdout");
    # Closing a standard stream only forgets it: fd 1 stays usable.
    assert(out.close().is_ok(), "close stdout");
    assert(io.File.stdout().write_all("|still-open").is_ok(), "stdout again");
    assert(io.File.stderr().is_open() && io.File.stdin().is_open(), "stderr, stdin");
    return 0;
}
"##;

const IMPORT_NAMES_PROGRAM: &str =
    "import [Path as P] from io;\nmain(): int { return P(\"ab\").to_string().size() as int - 2; }";

#[test]
fn stdout_is_a_file() {
    let out = assert_runs("stdout", STDOUT_PROGRAM);
    assert_eq!(out, "io-stdout-ok|still-open");
}

const PRINT_ORDER_PROGRAM: &str = r##"
import io;

main(): int {
    print("one");
    assert(io.File.stdout().write_all("two\n").is_ok(), "write two");
    print("three");
    assert(io.File.stdout().write_all("four\n").is_ok(), "write four");
    print("five");
    return 0;
}
"##;

/// `print` buffers in C stdio and `File.stdout()` writes the descriptor
/// directly; with stdout a pipe, the File write flushes `print`'s buffer
/// first so the lines come out in program order.
#[test]
fn print_and_stdout_keep_order() {
    let out = assert_runs("print_order", PRINT_ORDER_PROGRAM);
    // On Windows, C stdio writes `print`'s newline as "\r\n".
    assert_eq!(out.replace("\r\n", "\n"), "one\ntwo\nthree\nfour\nfive\n");
}

#[test]
fn file_closes_on_last_release() {
    let scratch = scratch_name("close");
    assert_runs("close", &close_program(&scratch));
}

#[test]
fn io_is_a_module_not_prelude() {
    std::env::set_current_dir(repo_root()).unwrap();
    // Without an import, io is not loaded at all: Path is unknown.
    let err = build("no_import", "main(): int { var p = Path(\"a\"); return p.to_string().size() as int; }")
        .expect_err("Path visible without importing io");
    assert!(err.contains("Path"), "unexpected error: {err}");
    let _ = std::fs::remove_dir_all(source_dir("no_import"));
    // `import io` finds runtime/io through the runtime search path, and
    // `import [..] from io` binds names unqualified.
    assert_runs("import_names", IMPORT_NAMES_PROGRAM);
    // The platform layer and helpers are not part of the module's API.
    let err = pepper_driver::compiler::check_with_runtime(
        "private.pep",
        "import io;\nmain(): int { var t = io._io_sys_temp_dir(); return 0; }",
    )
    .expect_err("io exports its platform layer");
    assert!(err.contains("_io_sys_temp_dir"), "unexpected error: {err}");
    // The discovered prelude is the top-level runtime/*.pep only.
    let (sources, _, _) = pepper_driver::runtime::discover();
    assert!(!sources.is_empty());
    assert!(sources.iter().all(|p| p.parent().unwrap().file_name().unwrap() == "runtime"), "{sources:?}");
    assert!(repo_root().join("runtime/io/module.pep").is_file());
}

/// Every program the host tests build and run, as (name, source): the
/// simulated-host tests push each one through the same pipeline for every
/// other platform.
fn all_programs() -> Vec<(&'static str, String)> {
    vec![
        ("path", PATH_PROGRAM.to_string()),
        ("fs", fs_program("x")),
        ("stdout", STDOUT_PROGRAM.to_string()),
        ("close", close_program("x")),
        ("import_names", IMPORT_NAMES_PROGRAM.to_string()),
    ]
}

pub(crate) const SIMULATED_HOSTS: [(&str, &str); 6] = [
    ("windows", "x86_64"),
    ("windows", "aarch64"),
    ("macos", "x86_64"),
    ("macos", "aarch64"),
    ("linux", "x86_64"),
    ("linux", "aarch64"),
];

/// Compile `source` with the host simulated as `os`/`arch` — the same
/// platform filter, sema and LLVM codegen that host runs — and hand the
/// generated module to `then`. The result can be neither linked nor run as
/// a native program here.
pub(crate) fn with_codegen_as<R>(
    os: &str,
    arch: &str,
    name: &str,
    source: &str,
    then: impl FnOnce(&mut CodeGenerator, &mut pepper_sema::Module) -> Result<R, String>,
) -> Result<R, String> {
    std::env::set_current_dir(repo_root()).unwrap();
    let (src, dir) = write_source(&format!("{name}_{os}_{arch}"), source);
    let result = pepper_sema::with_simulated_host(os, arch, || {
        let options = pepper_driver::Options::parse_from(vec!["pepper".to_string(), src.to_string_lossy().into_owned()]);
        let mut module = pepper_driver::compiler::compile(&options, "main")?;
        let ctx = inkwell::context::Context::create();
        let mut generator = CodeGenerator::new(&ctx, "main");
        then(&mut generator, &mut module)
    });
    let _ = std::fs::remove_dir_all(dir);
    result
}

/// The platform layer for `os`/`arch` must type-check and produce a valid
/// module that references that platform's C functions.
fn codegen_as(os: &str, arch: &str, name: &str, source: &str) -> Result<(), String> {
    with_codegen_as(os, arch, name, source, |generator, module| {
        generator.generate(module).map_err(|d| module.sources.render(&d))?;
        generator.module.verify().map_err(|e| format!("invalid IR: {}", e.to_string()))?;
        let ir = generator.module.to_string();
        // Spot-check that the simulated platform's layer is the one that
        // survived.
        let expect = match os {
            "windows" => "CreateFileW",
            "macos" if arch == "x86_64" => "stat$INODE64",
            "macos" => "@lstat(",
            _ => "@statx(",
        };
        if !ir.contains(expect) {
            return Err(format!("IR does not reference {expect}"));
        }
        Ok(())
    })
}

#[test]
fn other_platforms_compile() {
    let cases: Vec<_> = SIMULATED_HOSTS.iter().flat_map(|&host| all_programs().into_iter().map(move |p| (host, p))).collect();
    let failures: Vec<String> = support::parallel_map(&cases, |((os, arch), (name, source))| {
        codegen_as(os, arch, name, source).err().map(|e| format!("{os}/{arch} {name}: {e}"))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[cfg(unix)]
unsafe extern "C" {
    fn dlsym(handle: *mut std::ffi::c_void, name: *const std::ffi::c_char) -> *mut std::ffi::c_void;
}

/// Stands in for a C function this host does not have (kernel32 on a
/// simulated Windows): the path program never calls one.
#[cfg(unix)]
extern "C" fn unresolved_extern() {
    eprintln!("the program called a C function this host does not have");
    std::process::abort();
}

/// Path syntax is pure Pepper, so the path program runs, in-process by JIT,
/// with every simulated host's rules: Windows separators, drives and UNC
/// prefixes are checked on any Unix host. (A failed assert aborts the test
/// process after printing its message.)
#[cfg(unix)]
#[test]
fn path_functions_on_every_platform() {
    #[cfg(target_os = "macos")]
    let rtld_default = -2isize as *mut std::ffi::c_void;
    #[cfg(not(target_os = "macos"))]
    let rtld_default: *mut std::ffi::c_void = std::ptr::null_mut();
    // The raw handle is not Sync; carry it across threads as an address.
    let rtld_default = rtld_default as usize;
    let codes = support::parallel_map(&SIMULATED_HOSTS, |&(os, arch)| {
        with_codegen_as(os, arch, "path_jit", PATH_PROGRAM, |generator, module| {
            let ee = generator.jit_engine_mapped(module, |name| {
                let c = std::ffi::CString::new(name).ok()?;
                let found = unsafe { dlsym(rtld_default as *mut std::ffi::c_void, c.as_ptr()) };
                found.is_null().then_some(unresolved_extern as *const () as usize)
            })?;
            CodeGenerator::jit_call_i32(&ee, "main")
        })
    });
    for ((os, arch), code) in SIMULATED_HOSTS.iter().zip(codes) {
        assert_eq!(code, Ok(0), "path program as {os}/{arch}");
    }
}