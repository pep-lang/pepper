# The Pepper releases on GitHub, and downloading a toolchain's archive.
#
# The releases come from GitHub's API, or from `PEPPER_INSTALL_RELEASES_URL`
# when that is set: a URL serving the same JSON, for a mirror or a test.
# `GITHUB_TOKEN` or `GH_TOKEN` is sent to GitHub's API, which raises its
# limit on requests an hour, and to nothing else.

import digest;
import http;
import [File, Path] from io;
import json;
import os;
import text;
import toolchain;

# GitHub's list of the repository's releases, newest first. The repository
# also has `vsix-*` and `llvm-*` releases, which are skipped.
const RELEASES_URL = "https://api.github.com/repos/pep-lang/pepper/releases?per_page=100";
const GITHUB_API = "https://api.github.com/";

# One toolchain release for this machine: its version and its archive.
export struct Release {
    var version = toolchain.Version();
    # `pepper-0.3.0-linux-x64.tar.gz`
    var archive_name = "";
    var archive_url = "";
    var checksum_url = "";

    construct() {}
}

# What the API says of a release, and of each file attached to one.
struct _GithubAsset {
    var name = "";
    var url = "";

    construct() {}
}

struct _GithubRelease {
    var tag_name = "";
    var draft = false;
    var prerelease = false;
    var assets = Array<_GithubAsset>();

    construct() {}
}

# The URL the releases are listed from.
export releases_url(): String {
    var variable = os.environment("PEPPER_INSTALL_RELEASES_URL");
    if (variable.is_value() and !variable.value().is_empty) {
        return variable.value();
    }
    return RELEASES_URL;
}

# The archive of the toolchain `version` for `target`: a `.zip` for
# Windows, a `.tar.gz` for the rest.
export archive_name(version: toolchain.Version, target: String): String {
    var extension = target.starts_with("windows") ? ".zip" : ".tar.gz";
    return $"pepper-{version.to_string()}-{target}{extension}";
}

# Lists the releases at `url` that have an archive and its `.sha256` for
# `target`, newest first.
export fetch_releases(url: String, target: String): Result<Array<Release>> {
    var body = download(url, "application/vnd.github+json")?;
    return parse_releases(text.Utf8.decode_lossy(body), target);
}

# The releases in `text`, GitHub's JSON list of releases, that have an
# archive and its `.sha256` for `target`, newest first. Drafts are left
# out, and so are tags that are not `v<version>`. A prerelease is listed
# only when its tag names one (`v0.4.0-dev`, the build of main), which only
# a spec naming it exactly picks.
export parse_releases(text: String, target: String): Result<Array<Release>> {
    var decoded = json.decode<Array<_GithubRelease>>(text);
    if (decoded.is_err()) {
        return Result<Array<Release>>.Err($"cannot read the list of releases: {decoded.error().to_string()}");
    }
    var releases = Array<Release>();
    for (var listed in decoded.value()) {
        if (listed.draft or !listed.tag_name.starts_with("v")) {
            continue;
        }
        var version = toolchain.parse_version(listed.tag_name);
        if (version.is_empty() or listed.prerelease != !version.value().prerelease.is_empty) {
            continue;
        }
        var release = Release();
        release.version = version.value();
        release.archive_name = archive_name(version.value(), target);
        for (var asset in listed.assets) {
            if (asset.name == release.archive_name) {
                release.archive_url = asset.url;
            } else if (asset.name == release.archive_name + ".sha256") {
                release.checksum_url = asset.url;
            }
        }
        if (!release.archive_url.is_empty and !release.checksum_url.is_empty) {
            releases.append(release);
        }
    }
    releases.sort((a, b) => b.version.compare(a.version));
    return Result<Array<Release>>.ok(releases);
}

# Downloads `release`'s archive to the file `destination`, and checks it
# against its `.sha256`. It is streamed, since an archive can be larger
# than a response the client reads into memory.
export fetch_archive(release: Release, destination: Path): Result<void> {
    var checksum = download(release.checksum_url, "application/octet-stream")?;
    var fields = text.Utf8.decode_lossy(checksum).trim().split(" ");
    var expected = fields[0].lower();
    if (expected.size != 64) {
        return Result<void>.Err($"{release.archive_name}.sha256 does not hold a sha256");
    }
    var response = http.Client().open(_request(release.archive_url, "application/octet-stream"));
    if (response.is_err()) {
        return Result<void>.Err($"cannot download {release.archive_url}: {response.error().message}");
    }
    if (!response.value().is_success()) {
        return Result<void>.Err(
            $"cannot download {release.archive_url}: {response.value().status} {response.value().reason}"
        );
    }
    var file = File.create(destination);
    if (file.is_err()) {
        return Result<void>.Err($"cannot write {destination.to_string()}: {file.error().message}");
    }
    var hasher = digest.Sha256();
    for (var chunk in response.value().reader().chunks(65536)) {
        if (chunk.is_err()) {
            return Result<void>.Err($"cannot download {release.archive_url}: {chunk.error().message}");
        }
        hasher.update(chunk.value());
        var written = file.value().write_all(chunk.value());
        if (written.is_err()) {
            return Result<void>.Err($"cannot write {destination.to_string()}: {written.error().message}");
        }
    }
    file.value().close();
    var actual = digest.to_hex(hasher.finish());
    if (actual != expected) {
        return Result<void>.Err(
            $"{release.archive_name} does not match its .sha256: sha256 {actual}, expected {expected}"
        );
    }
    return Result<void>.ok();
}

# Downloads `url`, asking for `accept`. An asset's API URL answers with
# its contents when asked for `application/octet-stream`, by a redirect
# the client follows (and does not send the token on).
export download(url: String, accept: String): Result<u8[]> {
    var response = http.Client().send(_request(url, accept));
    if (response.is_err()) {
        return Result<u8[]>.Err($"cannot download {url}: {response.error().message}");
    }
    var got = response.value();
    if (!got.is_success()) {
        return Result<u8[]>.Err($"cannot download {url}: {got.status} {got.reason}");
    }
    return Result<u8[]>.ok(got.body());
}

# A request for `url`, asking for `accept`.
_request(url: String, accept: String): http.Request {
    var request = http.Request("GET", url);
    request.headers.set("Accept", accept);
    # GitHub's API refuses requests without one.
    request.headers.set("User-Agent", "pep-install");
    var token = _token();
    if (url.starts_with(GITHUB_API) and !token.is_empty) {
        request.headers.set("Authorization", "Bearer " + token);
    }
    return request;
}

# The token to send GitHub's API: `GITHUB_TOKEN`, else `GH_TOKEN`.
_token(): String {
    for (var name in ["GITHUB_TOKEN", "GH_TOKEN"]) {
        var value = os.environment(name);
        if (value.is_value() and !value.value().is_empty) {
            return value.value();
        }
    }
    return "";
}
