# Toolchain versions (`0.3.0`), and the versions a command or a pin names:
#
#     0.3.0    exactly that release
#     0.3, 0   the newest release that starts so
#     latest   the newest release

## A toolchain's version: `major.minor.patch`.
export struct Version {
    var major: ulong = 0;
    var minor: ulong = 0;
    var patch: ulong = 0;

    construct() {}

    construct(major: ulong, minor: ulong, patch: ulong) {
        this.major = major;
        this.minor = minor;
        this.patch = patch;
    }

    ## Returns the version as `major.minor.patch`.
    to_string(): String {
        return $"{major}.{minor}.{patch}";
    }

    ## Returns a negative number, zero or a positive number as this version
    ## sorts before, with or after `other`.
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
        return 0;
    }

    ## Returns whether this is the same version as `other`.
    ==(other: Version): bool {
        return compare(other) == 0;
    }
}

## Returns the version `text` names exactly, `0.3.0` or a release tag's
## `v0.3.0`, or none when it names no single version.
export parse_version(text: String): Version? {
    var spec = parse_spec(text.starts_with("v") ? text.substr(1, text.length) : text);
    if (spec.is_empty() or spec.value().parts.count != 3) {
        return Optional<Version>.Empty;
    }
    var parts = spec.value().parts;
    return Optional<Version>.Value(Version(parts[0], parts[1], parts[2]));
}

## The versions a command or a pin names: `0.3.0`, `0.3`, `0` or `latest`.
export struct VersionSpec {
    ## The numbers written, from the major one: three for an exact version,
    ## none for `latest`.
    var parts = Array<ulong>();

    construct() {}

    ## Whether it names one version exactly.
    var is_exact: bool {
        get {
            return parts.count == 3;
        }
    }

    ## Returns whether `version` is one of the versions it names.
    matches(version: Version): bool {
        var numbers = [version.major, version.minor, version.patch];
        for (var index in 0..parts.count) {
            if (parts[index] != numbers[index]) {
                return false;
            }
        }
        return true;
    }

    ## Returns it as written: `0.3`, or `latest`.
    to_string(): String {
        if (parts.is_empty) {
            return "latest";
        }
        var texts = Array<String>();
        for (var part in parts) {
            texts.append($"{part}");
        }
        return ".".join(texts);
    }
}

## Returns the versions `text` names (`0.3.0`, `0.3`, `0` or `latest`), or
## none when it is not one of those.
export parse_spec(text: String): VersionSpec? {
    var spec = VersionSpec();
    if (text == "latest") {
        return Optional<VersionSpec>.Value(spec);
    }
    var parts = text.split(".");
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
    return Optional<VersionSpec>.Value(spec);
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
