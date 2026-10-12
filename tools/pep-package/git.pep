# Fetching packages with git: what a repository offers (`git ls-remote`),
# and checking a commit out into `.pep/deps`. Authentication is git's
# concern (credential helpers, SSH keys).

import [Directory, Path] from io;
import os;
import process;
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
# naming the commit it points to.
export remote_refs(url: String): Result<Array<RemoteRef>> {
    var listed = git(["ls-remote", url]);
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

# Makes `directory` a checkout of `commit` from `url`: clones it when it is
# missing, fetches when the commit is not there yet, and checks the commit
# out (detached). Returns the full commit.
export check_out(url: String, directory: Path, commit: String): Result<String> {
    var at = checked_out(directory);
    if (at.is_value() and at.value().starts_with(commit)) {
        return Result<String>.Ok(at.value());
    }
    if (at.is_empty()) {
        if (directory.exists()) {
            var removed = remove_tree(directory);
            if (removed.is_err()) {
                return Result<String>.Err($"cannot remove {directory.to_string()}: {removed.error().message}");
            }
        }
        var parent = directory.parent();
        if (parent.is_value()) {
            Directory.create_all(parent.value());
        }
        var cloned = git(["clone", "--quiet", "--no-checkout", url, directory.to_string()]);
        if (cloned.is_err()) {
            return Result<String>.Err(cloned.error().message);
        }
    }
    var dir = directory.to_string();
    var known = git(["cat-file", "-e", commit + "^{commit}"], dir);
    if (known.is_err()) {
        var fetched = git(["fetch", "--quiet", "--tags", url, "+refs/heads/*:refs/remotes/origin/*"], dir);
        if (fetched.is_err()) {
            return Result<String>.Err(fetched.error().message);
        }
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
