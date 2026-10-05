# Which toolchain a folder uses. The first of these that names one wins:
#
#   1. `pepper +0.3.0 build ...`;
#   2. the `PEPPER_TOOLCHAIN` environment variable;
#   3. `toolchain = "0.3"` in `[package]` of the nearest pep.toml;
#   4. the default `pepper install use` set.

import [File, Path] from io;
import toml;
import "home";
import "version";

## Where the toolchain a folder uses is named.
export enum Source {
    ## `pepper +<version>`.
    Override,
    ## The `PEPPER_TOOLCHAIN` environment variable.
    Environment,
    ## The `toolchain` field of a project's pep.toml.
    Project,
    ## The default `pepper install use` set.
    Default,
}

## The toolchain a folder uses, and why.
export struct Choice {
    ## The versions it names.
    var spec = VersionSpec();
    var source = Source.Default;
    ## The pep.toml that pins it, for `Source.Project`.
    var manifest = Path();
    ## The newest installed toolchain `spec` names, if any is installed.
    var version = Optional<Version>.Empty;

    construct() {}

    ## Returns why it is the one used: `pinned by /work/app/pep.toml`.
    reason(): String {
        return match (source) {
            Override => $"named by 'pepper +{spec.to_string()}'",
            Environment => "named by PEPPER_TOOLCHAIN",
            Project => $"pinned by {manifest.to_string()}",
            Default => "the default",
        };
    }
}

## Returns the toolchain `directory` uses: `override` (the version after
## `pepper +`, or empty), else `environment` (`PEPPER_TOOLCHAIN`'s value,
## or empty), else the `toolchain` of the nearest pep.toml at or above
## `directory`, else `home`'s default. None when nothing names one; an
## error when the one that wins is not a version or its pep.toml cannot be
## read.
export choose_toolchain(home: Home, override: String, environment: String, directory: Path): Result<Choice?> {
    if (!override.is_empty) {
        return _named(home, override, Source.Override, "'pepper +'");
    }
    if (!environment.is_empty) {
        return _named(home, environment, Source.Environment, "PEPPER_TOOLCHAIN");
    }
    var pinned = project_toolchain(directory)?;
    if (pinned.is_value()) {
        var (manifest, text) = pinned.value();
        var named = _named(home, text, Source.Project, $"'toolchain' in {manifest.to_string()}")?;
        named.value().manifest = manifest;
        return Result<Choice?>.ok(named);
    }
    var default_version = home.default_version();
    if (default_version.is_empty()) {
        return Result<Choice?>.ok(Optional<Choice>.Empty);
    }
    var spec = parse_spec(default_version.value().to_string()).value();
    return Result<Choice?>.ok(Optional<Choice>.Value(_choice(home, spec, Source.Default)));
}

# The choice of the version `text`, which `where` names.
_named(home: Home, text: String, source: Source, where: String): Result<Choice?> {
    var spec = parse_spec(text);
    if (spec.is_empty()) {
        return Result<Choice?>.Err($"{where} names '{text}', not a version such as 0.3.0, 0.3 or latest");
    }
    return Result<Choice?>.ok(Optional<Choice>.Value(_choice(home, spec.value(), source)));
}

_choice(home: Home, spec: VersionSpec, source: Source): Choice {
    var choice = Choice();
    choice.spec = spec;
    choice.source = source;
    choice.version = newest_match(home.installed(), spec);
    return choice;
}

## Returns the nearest pep.toml at or above `directory` and the `toolchain`
## its `[package]` pins, when it pins one. An error when that pep.toml
## cannot be read or its `toolchain` is not a string.
export project_toolchain(directory: Path): Result<(Path, String)?> {
    var manifest = find_manifest(directory);
    if (manifest.is_empty()) {
        return Result<(Path, String)?>.ok(Optional<(Path, String)>.Empty);
    }
    var path = manifest.value();
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return Result<(Path, String)?>.Err($"cannot read {path.to_string()}: {text.error().message}");
    }
    var parsed = toml.parse(text.value(), path = path.to_string());
    if (parsed.is_err()) {
        return Result<(Path, String)?>.Err(parsed.error().to_string());
    }
    var pinned = parsed.value().lookup("package.toolchain");
    if (pinned.is_empty()) {
        return Result<(Path, String)?>.ok(Optional<(Path, String)>.Empty);
    }
    var name = pinned.value().as_string();
    if (name.is_empty()) {
        return Result<(Path, String)?>.Err(
            $"{path.to_string()}: '[package]' 'toolchain' must be a string, such as \"0.3\""
        );
    }
    return Result<(Path, String)?>.ok(Optional<(Path, String)>.Value((path, name.value())));
}

## Returns the nearest pep.toml at or above `directory`, if any.
export find_manifest(directory: Path): Path? {
    var at = Optional<Path>.Value(directory);
    while (at.is_value()) {
        var candidate = at.value().join("pep.toml");
        if (candidate.is_file()) {
            return Optional<Path>.Value(candidate);
        }
        at = at.value().parent();
    }
    return Optional<Path>.Empty;
}
