# Fetching packages with git: what a repository offers (`git ls-remote`),
# and checking a commit out into `.pep/deps` from the download cache every
# project shares, a bare repository per package in the Pepper home.
# Authentication is git's concern (credential helpers, SSH keys).

import [Directory, File, Path] from io;
import io;
import os;
import process;
import toolchain;
import "tree";

# The web address of host `host` (`github`): `https://github.com`, or the
# value of `PEPPER_PACKAGE_<HOST>_URL` when set (a mirror, or a folder of
# repositories in tests).
export host_url(host: String): String {
    var variable = os.environment("PEPPER_PACKAGE_" + host.upper() + "_URL");
    if (variable.is_value() and !variable.value().is_empty) {
        return variable.value();
    }
    if (host == "gitlab") {
        return "https://gitlab.com";
    }
    if (host == "codeberg") {
        return "https://codeberg.org";
    }
    return "https://github.com";
}

# The domain a host's packages are kept under in `.pep/deps`.
export host_domain(host: String): String {
    if (host == "gitlab") {
        return "gitlab.com";
    }
    if (host == "codeberg") {
        return "codeberg.org";
    }
    return "github.com";
}

# The address git clones `repository` (`owner/name`) on `host` from.
export repository_url(host: String, repository: String): String {
    return host_url(host) + "/" + repository + ".git";
}

# Runs git with `arguments`, in `directory` when it is not empty, and
# returns what it printed, or what went wrong.
export git(arguments: Array<String>, directory: String = ""): Result<String> {
    # No fsmonitor daemon for a checkout pep-package owns: each would
    # outlive the command (with `core.fsmonitor = true` in a user's config).
    var command = process.Command("git").arguments(["-c", "core.fsmonitor=false"]).arguments(arguments);
    if (!directory.is_empty) {
        command.working_directory(Path(directory));
    }
    # Never stop to ask for a password: a repository that needs one fails.
    # Git Credential Manager (Windows) asks in a window unless told not to.
    command.environment("GIT_TERMINAL_PROMPT", "0").environment("GCM_INTERACTIVE", "never");
    var output = command.run();
    if (output.is_err()) {
        return Result<String>.Err($"cannot run git: {output.error().message}");
    }
    var result = output.value();
    if (!result.status.success()) {
        var said = result.stderr.trim();
        return Result<String>.Err($"git {" ".join(arguments)} failed" + (said.is_empty ? "" : ": " + said));
    }
    return Result<String>.Ok(result.stdout);
}

# Whether git is on the PATH.
export has_git(): bool {
    return process.find_executable("git").is_value();
}

# A reference a repository offers, and the commit it points to.
export struct RemoteRef {
    # `refs/tags/v1.2.0`, `refs/heads/main`, `HEAD`.
    var name: String = "";
    var commit: String = "";

    construct() {}

    construct(name: String, commit: String) {
        this.name = name;
        this.commit = commit;
    }
}

# The references `url` offers (`git ls-remote`), with an annotated tag
# naming the commit it points to. `url` may be a remote of the repository
# in `directory`, such as `origin`.
export remote_refs(url: String, directory: String = ""): Result<Array<RemoteRef>> {
    var listed = git(["ls-remote", url], directory);
    if (listed.is_err()) {
        return Result<Array<RemoteRef>>.Err(listed.error().message);
    }
    var refs = Array<RemoteRef>();
    for (var line in listed.value().lines()) {
        var split = line.split_once("\t");
        if (split.is_empty()) {
            continue;
        }
        var (commit, name) = split.value();
        if (name.ends_with("^{}")) {
            # The commit an annotated tag points to: it replaces the tag's
            # own object, listed just before.
            var tag = name.substr(0, name.length - 3);
            for (var index in 0..refs.count) {
                if (refs[index].name == tag) {
                    refs[index] = RemoteRef(tag, commit);
                }
            }
            continue;
        }
        refs.append(RemoteRef(name, commit));
    }
    return Result<Array<RemoteRef>>.Ok(refs);
}

# The commit `directory`'s checkout is at, if it is a git checkout.
export checked_out(directory: Path): Optional<String> {
    if (!directory.join(".git").exists()) {
        return Optional<String>.Empty;
    }
    var head = git(["rev-parse", "HEAD"], directory.to_string());
    if (head.is_err()) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(head.value().trim());
}

# Why `--offline` cannot use `directory` for `commit`.
export not_held_offline(directory: Path, commit: String): String {
    return $"--offline, and neither {directory.to_string()} nor the package cache holds the commit {commit.substr(0, 12)}; run 'pepper package fetch' without --offline (or PEPPER_OFFLINE) first";
}

# The download cache every project shares: `cache/packages` in the Pepper
# home (`PEPPER_HOME`).
export cache_dir(): Path {
    return toolchain.find_home().root.join("cache").join("packages");
}

# Where the cache keeps `repository` (`owner/name`) on `host`: its bare
# repository is this path with `.git` added, its archives (fetched without
# git) `<this>/<commit>.tar.gz`, and its lock this path with `.lock` added.
export cached_package(host: String, repository: String): Path {
    var dir = cache_dir().join(host_domain(host));
    for (var part in repository.split("/")) {
        dir = dir.join(part);
    }
    return dir;
}

# Takes the cache's lock on `repository` on `host`, which the returned file
# holds until it is closed or destroyed, so processes fetching the same
# package take turns.
export lock_cache(host: String, repository: String): Result<File> {
    var path = Path(cached_package(host, repository).to_string() + ".lock");
    var parent = path.parent();
    if (parent.is_value()) {
        Directory.create_all(parent.value());
    }
    var opened = io.OpenOptions().write(true).create(true).open(path);
    if (opened.is_err()) {
        return Result<File>.Err($"cannot open {path.to_string()}: {opened.error().message}");
    }
    var held = opened.value().lock();
    if (held.is_err()) {
        return Result<File>.Err($"cannot lock {path.to_string()}: {held.error().message}");
    }
    return Result<File>.Ok(opened.value());
}

# Makes `directory` a checkout of `commit` of `repository` on `host`:
# clones it when it is missing, fetches when the commit is not there yet,
# and checks the commit out (detached). Returns the full commit. `offline`
# fails rather than reach the network.
export check_out(
    host: String, repository: String, directory: Path, commit: String, offline: bool = false
): Result<String> {
    var at = checked_out(directory);
    if (at.is_value() and at.value().starts_with(commit)) {
        return Result<String>.Ok(at.value());
    }
    var dir = directory.to_string();
    var fetched = _fetch_commit(host, repository, directory, commit, offline);
    if (fetched.is_err()) {
        return Result<String>.Err(fetched.error().message);
    }
    var switched = git(["checkout", "--quiet", "--detach", commit], dir);
    if (switched.is_err()) {
        return Result<String>.Err(switched.error().message);
    }
    var head = checked_out(directory);
    if (head.is_empty()) {
        return Result<String>.Err($"cannot read the commit of {dir}");
    }
    return Result<String>.Ok(head.value());
}

# Makes the clone `directory` hold `commit`, unless it does already, from
# the cache, which fetches it first when it lacks it. A missing clone is
# cloned from the cache: git hard-links the objects where the file system
# allows (copying them across drives), so the clone does not need the
# cache afterwards. `offline` fails rather than fetch.
_fetch_commit(host: String, repository: String, directory: Path, commit: String, offline: bool): Result<void> {
    var dir = directory.to_string();
    var cloned = directory.join(".git").exists();
    if (cloned and git(["cat-file", "-e", commit + "^{commit}"], dir).is_ok()) {
        return Result<void>.ok();
    }
    var lock = lock_cache(host, repository);
    if (lock.is_err()) {
        return Result<void>.Err(lock.error().message);
    }
    var url = repository_url(host, repository);
    var cached = _cache_commit(host, repository, url, directory, commit, offline);
    if (cached.is_err()) {
        return Result<void>.Err(cached.error().message);
    }
    var (bare, full) = cached.value();
    if (cloned) {
        var fetched = git(["fetch", "--quiet", bare.to_string(), full], dir);
        return fetched.is_err() ? Result<void>.Err(fetched.error().message) : Result<void>.ok();
    }
    if (directory.exists()) {
        var removed = remove_tree(directory);
        if (removed.is_err()) {
            return Result<void>.Err($"cannot remove {dir}: {removed.error().message}");
        }
    }
    var parent = directory.parent();
    if (parent.is_value()) {
        Directory.create_all(parent.value());
    }
    var made = git(["clone", "--quiet", "--no-checkout", bare.to_string(), dir]);
    if (made.is_err()) {
        return Result<void>.Err(made.error().message);
    }
    # The clone names the package's own address, not the cache's.
    var named = git(["remote", "set-url", "origin", url], dir);
    return named.is_err() ? Result<void>.Err(named.error().message) : Result<void>.ok();
}

# Makes the cache's bare repository of `repository` on `host` hold
# `commit`, made and fetched from `url` when it lacks it; `offline` fails
# instead, naming `directory`. Returns the repository and the full commit.
# The caller holds `lock_cache`.
_cache_commit(
    host: String, repository: String, url: String, directory: Path, commit: String, offline: bool
): Result<(Path, String)> {
    var bare = Path(cached_package(host, repository).to_string() + ".git");
    if (!bare.is_directory()) {
        if (offline) {
            return Result<(Path, String)>.Err(not_held_offline(directory, commit));
        }
        # Made beside it and renamed, so an interrupted one leaves none.
        var partial = Path(bare.to_string() + ".partial");
        if (partial.exists()) {
            var cleared = remove_tree(partial);
            if (cleared.is_err()) {
                return Result<(Path, String)>.Err($"cannot remove {partial.to_string()}: {cleared.error().message}");
            }
        }
        var made = git(["init", "--quiet", "--bare", partial.to_string()]);
        if (made.is_err()) {
            return Result<(Path, String)>.Err(made.error().message);
        }
        # Projects fetch a commit by its id, which no branch may name any more.
        var allowed = git(["config", "uploadpack.allowAnySHA1InWant", "true"], partial.to_string());
        if (allowed.is_err()) {
            return Result<(Path, String)>.Err(allowed.error().message);
        }
        var moved = File.rename(partial, bare);
        if (moved.is_err()) {
            return Result<(Path, String)>.Err(
                $"cannot move {partial.to_string()} to {bare.to_string()}: {moved.error().message}"
            );
        }
    }
    var at = bare.to_string();
    var full = git(["rev-parse", "--verify", "--quiet", commit + "^{commit}"], at);
    if (full.is_err()) {
        if (offline) {
            return Result<(Path, String)>.Err(not_held_offline(directory, commit));
        }
        # Forced, as a mirror may move a tag.
        var fetched = git(["fetch", "--quiet", url, "+refs/heads/*:refs/heads/*", "+refs/tags/*:refs/tags/*"], at);
        if (fetched.is_err()) {
            return Result<(Path, String)>.Err(fetched.error().message);
        }
        full = git(["rev-parse", "--verify", "--quiet", commit + "^{commit}"], at);
        if (full.is_err()) {
            return Result<(Path, String)>.Err($"{url} has no commit {commit}");
        }
    }
    return Result<(Path, String)>.Ok((bare, full.value().trim()));
}

# The text of `file` at `commit` of `repository` on `host`, read from the
# clone in `directory` without checking the commit out (a missing clone is
# made by checking `commit` out); none when the commit has no such file.
# `offline` reads only what the clone and the cache hold.
export file_at(
    host: String, repository: String, directory: Path, commit: String, file: String, offline: bool = false
): Result<Optional<String>> {
    if (checked_out(directory).is_empty()) {
        var checked = check_out(host, repository, directory, commit, offline);
        if (checked.is_err()) {
            return Result<Optional<String>>.Err(checked.error().message);
        }
    }
    var dir = directory.to_string();
    var fetched = _fetch_commit(host, repository, directory, commit, offline);
    if (fetched.is_err()) {
        return Result<Optional<String>>.Err(fetched.error().message);
    }
    # The commit is there, so a failure means it has no such file.
    var text = git(["show", commit + ":" + file], dir);
    return Result<Optional<String>>.Ok(text.is_ok() ? Optional<String>.Value(text.value()) : Optional<String>.Empty);
}
