# Toolchain versions (`0.3.0`, or a prerelease such as `0.4.0-dev`), and
# the versions a command or a pin names:
#
#     0.3.0      exactly that release
#     0.4.0-dev  exactly that prerelease
#     0.3, 0     the newest release that starts so
#     latest     the newest release
#
# Only a spec that names a prerelease exactly picks it: `0.4` and `latest`
# leave prereleases out, as in SemVer.

## A toolchain's version: `major.minor.patch`, or a prerelease
## `major.minor.patch-prerelease` such as `0.4.0-dev`.
export struct Version {
    var major: ulong = 0;
    var minor: ulong = 0;
    var patch: ulong = 0;
    ## The prerelease after the `-` (`dev`), or empty for a release.
    var prerelease = "";

    construct() {}

    construct(major: ulong, minor: ulong, patch: ulong) {
        this.major = major;
        this.minor = minor;
        this.patch = patch;
    }

    ## @param prerelease what follows the `-`, such as `dev`; empty for a
    ## release
    construct(major: ulong, minor: ulong, patch: ulong, prerelease: String) {
        this.major = major;
        this.minor = minor;
        this.patch = patch;
        this.prerelease = prerelease;
    }

    ## Returns the version as `major.minor.patch`, with `-prerelease` after
    ## it for a prerelease.
    to_string(): String {
        if (!prerelease.is_empty) {
            return $"{major}.{minor}.{patch}-{prerelease}";
        }
        return $"{major}.{minor}.{patch}";
    }

    ## Returns a negative number, zero or a positive number as this version
    ## sorts before, with or after `other`. A prerelease sorts before its
    ## release (`0.4.0-dev` before `0.4.0`), and prereleases of one version
    ## by their text.
    compare(other: Version): int {
        if (major != other.major) {
            return major < other.major ? -1 : 1;
        }
        if (minor != other.minor) {
            return minor < other.minor ? -1 : 1;
        }
        if (patch != other.patch) {
            return patch < other.patch ? -1 : 1;
        }
        if (prerelease == other.prerelease) {
            return 0;
        }
        if (prerelease.is_empty) {
            return 1;
        }
        if (other.prerelease.is_empty) {
            return -1;
        }
        return prerelease.compare(other.prerelease) < 0 ? -1 : 1;
    }

    ## Returns whether this is the same version as `other`.
    ==(other: Version): bool {
        return compare(other) == 0;
    }
}

## Returns the version `text` names exactly, `0.3.0` or a release tag's
## `v0.3.0` (or a prerelease, `0.4.0-dev`), or none when it names no single
## version.
export parse_version(text: String): Version? {
    var spec = parse_spec(text.starts_with("v") ? text.substr(1, text.length) : text);
    if (spec.is_empty() or spec.value().parts.count != 3) {
        return Optional<Version>.Empty;
    }
    var parts = spec.value().parts;
    return Optional<Version>.Value(Version(parts[0], parts[1], parts[2], spec.value().prerelease));
}

## The versions a command or a pin names: `0.3.0`, `0.4.0-dev`, `0.3`, `0`
## or `latest`.
export struct VersionSpec {
    ## The numbers written, from the major one: three for an exact version,
    ## none for `latest`.
    var parts = Array<ulong>();
    ## The prerelease an exact version names (`dev`), or empty.
    var prerelease = "";

    construct() {}

    ## Whether it names one version exactly.
    var is_exact: bool {
        get {
            return parts.count == 3;
        }
    }

    ## Returns whether `version` is one of the versions it names. A
    ## prerelease is one only of the spec that names it exactly.
    matches(version: Version): bool {
        if (version.prerelease != prerelease) {
            return false;
        }
        var numbers = [version.major, version.minor, version.patch];
        for (var index in 0..parts.count) {
            if (parts[index] != numbers[index]) {
                return false;
            }
        }
        return true;
    }

    ## Returns it as written: `0.3`, `0.4.0-dev`, or `latest`.
    to_string(): String {
        if (parts.is_empty) {
            return "latest";
        }
        var texts = Array<String>();
        for (var part in parts) {
            texts.append($"{part}");
        }
        if (!prerelease.is_empty) {
            return ".".join(texts) + "-" + prerelease;
        }
        return ".".join(texts);
    }
}

## Returns the versions `text` names (`0.3.0`, `0.4.0-dev`, `0.3`, `0` or
## `latest`), or none when it is not one of those. A prerelease is letters,
## digits and dots after the `-` of a full version.
export parse_spec(text: String): VersionSpec? {
    var spec = VersionSpec();
    if (text == "latest") {
        return Optional<VersionSpec>.Value(spec);
    }
    var numbers = text;
    var dash = text.find("-");
    if (dash >= 0) {
        numbers = text.substr(0, dash as ulong);
        spec.prerelease = text.substr(dash as ulong + 1, text.length);
        if (spec.prerelease.is_empty or !_is_prerelease(spec.prerelease)) {
            return Optional<VersionSpec>.Empty;
        }
    }
    var parts = numbers.split(".");
    if (parts.count > 3) {
        return Optional<VersionSpec>.Empty;
    }
    for (var part in parts) {
        var number = ulong.parse(part);
        # Decimal digits only, without a sign or a leading zero.
        if (number.is_empty() or to_string(number.value()) != part) {
            return Optional<VersionSpec>.Empty;
        }
        spec.parts.append(number.value());
    }
    if (!spec.prerelease.is_empty and parts.count != 3) {
        return Optional<VersionSpec>.Empty;
    }
    return Optional<VersionSpec>.Value(spec);
}

# Whether `text` is letters, digits and dots only.
_is_prerelease(text: String): bool {
    for (var byte in text.bytes()) {
        if (!byte.is_alphanumeric() and byte != '.') {
            return false;
        }
    }
    return true;
}

## Returns the newest of `versions` that `spec` names, if any.
export newest_match(versions: Array<Version>, spec: VersionSpec): Version? {
    var best = Optional<Version>.Empty;
    for (var version in versions) {
        if (!spec.matches(version)) {
            continue;
        }
        if (best.is_empty() or version.compare(best.value()) > 0) {
            best = Optional<Version>.Value(version);
        }
    }
    return best;
}
