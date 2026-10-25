# Build scripts: the Pepper program a package runs before its code is
# built (`[build]`'s `script`, else `build.pep`). The compiler runs it, and
# `pep-package` names the packages that have one when it fetches them.

import [File, Path] from io;
import toml;

## The file a package's build script is in when `[build]` names none.
export const BUILD_SCRIPT_FILE = "build.pep";

## Returns the build script of the package in `dir`: the file its
## pep.toml's `[build]` `script` names, relative to `dir`, else its
## `build.pep`, if there is one.
##
## @param dir the package's folder, holding its pep.toml
## @returns the script, none, or why pep.toml cannot be read or names a
##   script that does not exist
export build_script(dir: Path): Result<Path?, String> {
    var none = Result<Path?, String>.ok(Optional<Path>.Empty);
    var path = dir.join("pep.toml");
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return none;
    }
    var parsed = toml.parse(text.value(), path = path.to_string());
    if (parsed.is_err()) {
        return Result<Path?, String>.err(parsed.error().to_string());
    }
    var named = parsed.value().lookup("build.script");
    if (named.is_empty()) {
        var default_script = dir.join(Path(BUILD_SCRIPT_FILE));
        return default_script.is_file() ? Result<Path?, String>.ok(Optional<Path>.Value(default_script)) : none;
    }
    var file = named.value().as_string();
    if (file.is_empty()) {
        return Result<Path?, String>.err(
            $"{path.to_string()}: '[build]' 'script' must be a string, such as \"build.pep\""
        );
    }
    var script = dir.join(file.value());
    if (!script.is_file()) {
        return Result<Path?, String>.err(
            $"{path.to_string()}: '[build]' 'script' names {script.to_string()}, which does not exist"
        );
    }
    return Result<Path?, String>.ok(Optional<Path>.Value(script));
}
