# Semantic versions (`1.2.3`, a tag `v1.2.3`) and the ranges a pep.toml
# dependency's `version` writes, as Cargo reads them:
#
#     1.2, ^1.2     >=1.2.0, <2.0.0     (the leftmost nonzero part stays)
#     0.4, ^0.4     >=0.4.0, <0.5.0
#     ~1.2          >=1.2.0, <1.3.0
#     1.2.x, 1.2.*  >=1.2.0, <1.3.0
#     =1.2.3        exactly 1.2.3
#     >=1.0, <2     both comparisons
#     *             any version

# A version: `major.minor.patch`, with an optional prerelease after `-`
# (`1.0.0-beta.2`), which sorts before the release.
export struct Version {
    var major: ulong = 0;
    var minor: ulong = 0;
    var patch: ulong = 0;
    var prerelease: String = "";

    construct() {}

    construct(major: ulong, minor: ulong, patch: ulong) {
        this.major = major;
        this.minor = minor;
        this.patch = patch;
    }

    to_string(): String {
        var text = $"{major}.{minor}.{patch}";
        return prerelease.is_empty ? text : text + "-" + prerelease;
    }

    # Negative, zero or positive as this version sorts before, with or
    # after `other`.
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
}

# The version a tag names: `1.2.3` or `v1.2.3`, with an optional
# prerelease (`v1.0.0-rc.1`); none for any other tag.
export parse_version(text: String): Optional<Version> {
    var rest = text.starts_with("v") ? text.substr(1, text.length) : text;
    var prerelease = "";
    var split = rest.split_once("-");
    if (split.is_value()) {
        var (numbers, pre) = split.value();
        if (pre.is_empty) {
            return Optional<Version>.Empty;
        }
        rest = numbers;
        prerelease = pre;
    }
    var parts = rest.split(".");
    if (parts.count != 3) {
        return Optional<Version>.Empty;
    }
    var numbers = Array<ulong>();
    for (var part in parts) {
        var number = _number(part);
        if (number.is_empty()) {
            return Optional<Version>.Empty;
        }
        numbers.append(number.value());
    }
    var version = Version(numbers[0], numbers[1], numbers[2]);
    version.prerelease = prerelease;
    return Optional<Version>.Value(version);
}

# A number as semver writes one: decimal digits, no sign and no leading
# zero.
_number(text: String): Optional<ulong> {
    var number = ulong.parse(text);
    if (number.is_empty() or to_string(number.value()) != text) {
        return Optional<ulong>.Empty;
    }
    return number;
}

# One comparison of a range: `>=1.2.0`.
export struct Comparison {
    # One of `>=`, `>`, `<=`, `<` and `=`.
    var operator: String = "=";
    var version: Version = Version();

    construct() {}

    construct(operator: String, version: Version) {
        this.operator = operator;
        this.version = version;
    }

    matches(candidate: Version): bool {
        var order = candidate.compare(version);
        if (operator == ">=") {
            return order >= 0;
        }
        if (operator == ">") {
            return order > 0;
        }
        if (operator == "<=") {
            return order <= 0;
        }
        if (operator == "<") {
            return order < 0;
        }
        return order == 0;
    }
}

# A version range: every comparison must hold.
export struct VersionRange {
    # As written in pep.toml.
    var text: String = "";
    var comparisons: Array<Comparison> = __null;

    construct() {
        comparisons = Array<Comparison>();
    }

    # Whether `candidate` is in the range. A prerelease is in it only when
    # a comparison names a prerelease of the same version.
    matches(candidate: Version): bool {
        if (!candidate.prerelease.is_empty) {
            var named = false;
            for (var comparison in comparisons) {
                var v = comparison.version;
                if (!v.prerelease.is_empty
                    and v.major == candidate.major
                    and v.minor == candidate.minor
                    and v.patch == candidate.patch) {
                    named = true;
                }
            }
            if (!named) {
                return false;
            }
        }
        for (var comparison in comparisons) {
            if (!comparison.matches(candidate)) {
                return false;
            }
        }
        return true;
    }
}

# A partial version, `1`, `1.2` or `1.2.3`, with `x` or `*` allowed for a
# missing part: how many parts it gives, the version with the others 0, and
# whether it had a wildcard.
_partial(text: String): Result<(ulong, Version, bool)> {
    var numbers = Array<ulong>();
    var prerelease = "";
    var rest = text;
    var split = text.split_once("-");
    if (split.is_value()) {
        var (numbers_text, pre) = split.value();
        rest = numbers_text;
        prerelease = pre;
    }
    var parts = rest.split(".");
    if (parts.count > 3) {
        return Result<(ulong, Version, bool)>.Err($"'{text}' has more than three parts");
    }
    var wild = false;
    for (var part in parts) {
        if (part == "x" or part == "X" or part == "*") {
            wild = true;
            continue;
        }
        if (wild) {
            return Result<(ulong, Version, bool)>.Err($"'{text}' has a number after a wildcard");
        }
        var number = _number(part);
        if (number.is_empty()) {
            return Result<(ulong, Version, bool)>.Err($"'{part}' in '{text}' is not a number");
        }
        numbers.append(number.value());
    }
    var version = Version(
        numbers.count > 0 ? numbers[0] : 0, numbers.count > 1 ? numbers[1] : 0, numbers.count > 2 ? numbers[2] : 0
    );
    version.prerelease = prerelease;
    return Result<(ulong, Version, bool)>.Ok((numbers.count, version, wild));
}

# The version after the `given` leading parts of `v` are bumped: the upper
# bound of a caret or tilde range.
_bump(v: Version, part: ulong): Version {
    if (part == 0) {
        return Version(v.major + 1, 0, 0);
    }
    if (part == 1) {
        return Version(v.major, v.minor + 1, 0);
    }
    return Version(v.major, v.minor, v.patch + 1);
}

# Parses a range as pep.toml writes it (see the top of this file).
export parse_range(text: String): Result<VersionRange> {
    var range = VersionRange();
    range.text = text;
    var pieces = text.split(",");
    for (var raw in pieces) {
        var piece = raw.trim();
        if (piece.is_empty) {
            return Result<VersionRange>.Err($"version range '{text}' has an empty part");
        }
        if (piece == "*" or piece == "x" or piece == "X") {
            continue;
        }
        var operator = "^";
        for (var candidate in [">=", "<=", ">", "<", "=", "^", "~"]) {
            if (piece.starts_with(candidate)) {
                operator = candidate;
                piece = piece.substr(candidate.length, piece.length).trim();
                break;
            }
        }
        var parsed = _partial(piece);
        if (parsed.is_err()) {
            return Result<VersionRange>.Err($"invalid version range '{text}': {parsed.error().message}");
        }
        var (given, version, wild) = parsed.value();
        if (wild and operator == "^") {
            # `1.2.x` is every 1.2 version, like `=1.2`.
            operator = "=";
        }
        if (given == 0) {
            if (operator == "^" or operator == "~") {
                continue;
            }
            return Result<VersionRange>.Err($"invalid version range '{text}': '{operator}' needs a version");
        }
        if (operator == "^") {
            # Up to the leftmost nonzero part given; with only zeros, the
            # last part given.
            ulong keep = given - 1;
            if (version.major != 0) {
                keep = 0;
            } else if (version.minor != 0 and given > 1) {
                keep = 1;
            } else if (given > 2) {
                keep = 2;
            }
            range.comparisons.append(Comparison(">=", version));
            range.comparisons.append(Comparison("<", _bump(version, keep)));
        } else if (operator == "~") {
            range.comparisons.append(Comparison(">=", version));
            range.comparisons.append(Comparison("<", _bump(version, given == 1 ? 0 : 1)));
        } else if (operator == "=" and given < 3) {
            # `=1.2` is every 1.2.x.
            range.comparisons.append(Comparison(">=", version));
            range.comparisons.append(Comparison("<", _bump(version, given - 1)));
        } else if (operator == ">" and given < 3) {
            range.comparisons.append(Comparison(">=", _bump(version, given - 1)));
        } else if (operator == "<=" and given < 3) {
            range.comparisons.append(Comparison("<", _bump(version, given - 1)));
        } else {
            range.comparisons.append(Comparison(operator, version));
        }
    }
    return Result<VersionRange>.Ok(range);
}
