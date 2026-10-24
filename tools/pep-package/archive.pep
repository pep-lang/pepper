# Fetching packages without git: the host's `.tar.gz` of a commit,
# downloaded over HTTPS into the download cache and unpacked into
# `.pep/deps`, and the checksum of a package's files that pep.lock records
# for each package.
#
# The checksum covers the files, not the archive's bytes: hosts make their
# archives on demand and have changed how they compress them, which changes
# the bytes but not the files. It is the sha256 of every file, symlink and
# hard link the archive holds, in path order, so `git archive` of a
# checkout gives the same checksum as the host's archive of that commit.

import archive;
import compress;
import digest;
import http;
import [Directory, File, Path] from io;
import io;
import os;
import "git";
import "tree";

# The file in the unpacked package `directory` naming the commit it holds,
# since an archive has no `.git` to say so.
_commit_file(directory: Path): Path {
    return directory.join(".pep-commit");
}

# The address of the `.tar.gz` of `commit` of the repository `given`
# (`owner/name`, or a member's `owner/name#member`) on `host`, or under the address in `PEPPER_PACKAGE_<HOST>_ARCHIVE_URL`
# when that is set: `<address>/<owner>/<name>/<commit>.tar.gz`.
export archive_url(host: String, given: String, commit: String): String {
    var repository = repository_of(given);
    var variable = os.environment("PEPPER_PACKAGE_" + host.upper() + "_ARCHIVE_URL");
    if (variable.is_value() and !variable.value().is_empty) {
        return $"{variable.value()}/{repository}/{commit}.tar.gz";
    }
    if (host == "gitlab") {
        var parts = repository.split("/");
        var name = parts[parts.count - 1];
        return $"{host_url(host)}/{repository}/-/archive/{commit}/{name}-{commit}.tar.gz";
    }
    if (host == "codeberg") {
        return $"{host_url(host)}/{repository}/archive/{commit}.tar.gz";
    }
    return $"https://codeload.github.com/{repository}/tar.gz/{commit}";
}

# One entry the checksum covers.
struct _Hashed {
    var path: String = "";
    # `f` a file, `x` an executable file, `l` a symlink, `h` a hard link.
    var kind: String = "";
    # A file's contents, or a link's target.
    var data: u8[] = __null;

    construct(path: String, kind: String, data: u8[]) {
        this.path = path;
        this.kind = kind;
        this.data = data;
    }
}

# The checksum of the files in `tar`, an uncompressed tar archive, with
# the first `strip` components of each path dropped (a host's archive puts
# everything in one top-level folder).
export files_sha256(tar: u8[], strip: ulong): Result<String> {
    var reader = archive.TarReader(io.ByteReader(tar));
    var entries = Array<_Hashed>();
    while (true) {
        var next = reader.next_entry();
        if (next.is_err()) {
            return Result<String>.Err($"cannot read the archive: {next.error().message}");
        }
        if (next.value().is_empty()) {
            break;
        }
        var entry = next.value().value();
        var path = _strip(entry.path, strip);
        if (path.is_empty or entry.kind == archive.EntryKind.Directory or entry.kind == archive.EntryKind.Other) {
            continue;
        }
        if (entry.kind == archive.EntryKind.File) {
            var contents = reader.read_all();
            if (contents.is_err()) {
                return Result<String>.Err($"cannot read {entry.path} in the archive: {contents.error().message}");
            }
            # Whether anyone may run it: the one permission git keeps.
            var kind = (entry.mode & 73) != 0 ? "x" : "f";
            entries.append(_Hashed(path, kind, contents.value()));
        } else {
            var kind = entry.kind == archive.EntryKind.Symlink ? "l" : "h";
            var target = entry.kind == archive.EntryKind.HardLink ?
                _strip(entry.link_target, strip) :
                entry.link_target;
            entries.append(_Hashed(path, kind, target.bytes()));
        }
    }
    entries.sort((a, b) => a.path.compare(b.path));
    var hasher = digest.Sha256();
    for (var entry in entries) {
        hasher.update($"{entry.kind} {entry.path}\n{entry.data.count}\n");
        hasher.update(entry.data);
    }
    return Result<String>.Ok(hasher.finish_hex());
}

# `path` without its first `strip` components (and a trailing `/`).
_strip(path: String, strip: ulong): String {
    var parts = path.split("/");
    var kept = Array<String>();
    for (var index in 0..parts.count) {
        if (index >= strip and !parts[index].is_empty and parts[index] != ".") {
            kept.append(parts[index]);
        }
    }
    return "/".join(kept);
}

# The checksum of the files of `commit` in the git checkout `directory`,
# from `git archive`, which writes the files as the host's archive holds
# them: `export-ignore` honored, and no line-ending conversion beyond what
# the repository's own `.gitattributes` asks for, whatever this machine's
# `core.autocrlf` or `core.eol` (Git for Windows sets `core.autocrlf`).
export checkout_sha256(directory: Path, commit: String): Result<String> {
    var file = directory.join(".git").join("pep-package-archive.tar");
    var written = git(
        [
            "-c",
            "core.autocrlf=false",
            "-c",
            "core.eol=lf",
            "archive",
            "--format=tar",
            "--output=" + file.to_string(),
            commit
        ],
        directory.to_string()
    );
    if (written.is_err()) {
        return Result<String>.Err(written.error().message);
    }
    var bytes = File.read_bytes(file);
    File.remove(file);
    if (bytes.is_err()) {
        return Result<String>.Err($"cannot read {file.to_string()}: {bytes.error().message}");
    }
    return files_sha256(bytes.value(), 0);
}

# The commit the unpacked archive in `directory` holds, if it is one.
export unpacked(directory: Path): Optional<String> {
    var text = File.read_to_string(_commit_file(directory));
    if (text.is_err()) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(text.value().trim());
}

# The bytes of `file`.
_read(file: Path): Result<u8[]> {
    var bytes = File.read_bytes(file);
    return bytes.is_err() ?
        Result<u8[]>.Err($"cannot read {file.to_string()}: {bytes.error().message}") :
        Result<u8[]>.Ok(bytes.value());
}

# Writes `bytes` to `file` through a `.partial` file beside it, so a reader
# never sees half of it.
_store(file: Path, bytes: u8[]): Result<void> {
    var partial = Path(file.to_string() + ".partial");
    var parent = file.parent();
    if (parent.is_value()) {
        Directory.create_all(parent.value());
    }
    var written = File.write_bytes(partial, bytes);
    if (written.is_err()) {
        return Result<void>.Err($"cannot write {partial.to_string()}: {written.error().message}");
    }
    var moved = File.rename(partial, file);
    if (moved.is_err()) {
        return Result<void>.Err($"cannot move {partial.to_string()} to {file.to_string()}: {moved.error().message}");
    }
    return Result<void>.ok();
}

# Downloads `url`, following up to five redirects.
_download(url: String): Result<u8[]> {
    var client = http.Client();
    var at = url;
    for (var hop in 0..6) {
        var response = client.get(at);
        if (response.is_err()) {
            return Result<u8[]>.Err($"cannot download {at}: {response.error().message}");
        }
        var got = response.value();
        if (got.status >= 300 and got.status < 400) {
            var location = got.headers.get("Location");
            if (location.is_empty()) {
                return Result<u8[]>.Err($"{at} redirects with no Location");
            }
            at = _resolve_location(at, location.value());
            continue;
        }
        if (!got.is_success()) {
            return Result<u8[]>.Err($"cannot download {at}: {got.status} {got.reason}");
        }
        return Result<u8[]>.Ok(got.body());
    }
    return Result<u8[]>.Err($"cannot download {url}: too many redirects");
}

# The address a `Location` header names, relative to `base`.
_resolve_location(base: String, location: String): String {
    if (location.contains("://")) {
        return location;
    }
    var scheme = base.split_once("://");
    if (scheme.is_empty()) {
        return location;
    }
    var (protocol, rest) = scheme.value();
    var path = rest.split_once("/");
    var authority = path.is_value() ? path.value().0 : rest;
    return protocol + "://" + authority + (location.starts_with("/") ? location : "/" + location);
}

# Makes `directory` hold `commit` of `repository` on `host`, the host's
# archive of it, when it does not already. The archive comes from the
# download cache, which downloads it first when it lacks it; `offline`
# fails instead. When `expected` is not empty, the files must have that
# checksum. Returns the checksum.
export fetch_archive(
    host: String, repository: String, directory: Path, commit: String, expected: String, offline: bool = false
): Result<String> {
    var url = archive_url(host, repository, commit);
    var cached = cached_package(host, repository).join(commit + ".tar.gz");
    if (offline and !cached.is_file()) {
        return Result<String>.Err(not_held_offline(directory, commit));
    }
    var lock = lock_cache(host, repository);
    if (lock.is_err()) {
        return Result<String>.Err(lock.error().message);
    }
    # Another process may have stored it while this one waited.
    var from_cache = cached.is_file();
    var packed = from_cache ? _read(cached) : _download(url);
    if (packed.is_err()) {
        return Result<String>.Err(packed.error().message);
    }
    var tar = compress.DecompressReader(io.ByteReader(packed.value()), compress.Format.Gzip).read_all();
    if (tar.is_err()) {
        return Result<String>.Err($"{url} is not a .tar.gz: {tar.error().message}");
    }
    var sha256 = files_sha256(tar.value(), 1);
    if (sha256.is_err()) {
        return Result<String>.Err($"{url}: {sha256.error().message}");
    }
    if (!expected.is_empty and sha256.value() != expected) {
        return Result<String>.Err(
            $"the files of {host}:{repository} {commit.substr(0, 12)} do not match pep.lock: sha256 {sha256.value()}, expected {expected}"
        );
    }
    if (!from_cache) {
        var stored = _store(cached, packed.value());
        if (stored.is_err()) {
            return Result<String>.Err(stored.error().message);
        }
    }
    # Unpack beside the package's folder, and only a complete copy takes
    # its place.
    var partial = Path(directory.to_string() + ".partial");
    if (partial.exists()) {
        var cleared = remove_tree(partial);
        if (cleared.is_err()) {
            return Result<String>.Err($"cannot remove {partial.to_string()}: {cleared.error().message}");
        }
    }
    var extracted = archive.TarReader(io.ByteReader(tar.value())).extract(partial, strip_components = 1);
    if (extracted.is_err()) {
        remove_tree(partial);
        return Result<String>.Err($"cannot unpack {url}: {extracted.error().message}");
    }
    var marked = File.write_text(_commit_file(partial), commit + "\n");
    if (marked.is_err()) {
        return Result<String>.Err($"cannot write {_commit_file(partial).to_string()}: {marked.error().message}");
    }
    if (directory.exists()) {
        var removed = remove_tree(directory);
        if (removed.is_err()) {
            return Result<String>.Err($"cannot remove {directory.to_string()}: {removed.error().message}");
        }
    }
    var moved = File.rename(partial, directory);
    if (moved.is_err()) {
        return Result<String>.Err(
            $"cannot move {partial.to_string()} to {directory.to_string()}: {moved.error().message}"
        );
    }
    return Result<String>.Ok(sha256.value());
}
