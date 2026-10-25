## `--lib aar`: an Android library (`.aar`) an app's Gradle build adds as one
## dependency (see the book's "iOS and Android").
##
## The compiler builds the program's shared library once per Android ABI, by
## running itself with `--lib shared --target <triple>` (`build_for_targets`),
## then writes the `.aar`, a zip, by hand, so neither Gradle nor a JDK is
## needed: `jni/<abi>/lib<name>.so` for each ABI, the C header in
## `include/`, an `AndroidManifest.xml`, the empty `classes.jar`, `R.txt` and
## `res/` an `.aar` must hold, and OpenSSL's license when the library links
## it (`place_openssl_license`).

import compress;
import [File, Path] from io;
import compiler.link;
import "library";
import "xcframework";

## Builds the library of this build's program as the Android library
## `output`, named `name`: each ABI's shared library is built by `compiler`,
## side by side, with this build's `arguments` and `--lib shared --target
## <triple>`, into `build`.
##
## @param compiler the compiler to run for each target
## @param arguments this build's command line, the program first
## @param output the `.aar` to write
## @param name the library's name: `lib<name>.so`, which Java loads with
##   `System.loadLibrary("<name>")`
## @param build the build folder; each target builds in a folder of its own there
## @returns nothing, or why it cannot be built: empty when the compiler
##   printed why itself
export build_aar(compiler: Path, arguments: String[], output: Path, name: String, build: Path): Result<void, String> {
    var triples = Array<String>();
    for (var triple in link.supported_triples()) {
        if (triple.ends_with("-android")) {
            triples.append(triple);
        }
    }
    var library = $"lib{name}.so";
    var built = build_for_targets(compiler, arguments, ["--lib", "shared", "--bindings", "java"], triples, build, library);
    if (built.is_err()) {
        return built;
    }
    var empty = Array<u8>();
    var entries = Array<(String, u8[])>();
    entries.append(("AndroidManifest.xml", aar_manifest(name).bytes()));
    entries.append(("R.txt", empty));
    entries.append(("res/", empty));
    # Every target's header and license are the same: take the first's.
    var first = build.join(Path(triples[0]));
    var files = [
        (Path($"{name}.jar"), "classes.jar"),
        (Path($"{name}.h"), $"include/{name}.h"),
        (Path(OPENSSL_LICENSE), OPENSSL_LICENSE)
    ];
    for (var (file, entry) in files) {
        var path = first.join(file);
        if (path.is_file()) {
            var read = File.read_bytes(path);
            if (read.is_err()) {
                return Result<void, String>.err($"cannot read {path}: {read.error().message}");
            }
            entries.append((entry, read.value()));
        }
    }
    for (var triple in triples) {
        var path = build.join(Path(triple)).join(Path(library));
        var read = File.read_bytes(path);
        if (read.is_err()) {
            return Result<void, String>.err($"cannot read {path}: {read.error().message}");
        }
        entries.append(($"jni/{android_abi(triple)}/{library}", read.value()));
    }
    var written = File.write_bytes(output, zip_stored(entries));
    if (written.is_err()) {
        return Result<void, String>.err($"cannot write {output}: {written.error().message}");
    }
    return Result<void, String>.ok();
}

## The Android ABI name of the `-android` triple `triple`: `arm64-v8a` for
## `aarch64`, `x86_64` for `x86_64`.
##
## @param triple the target
## @returns the ABI, as `jni/` and `lib/` folders are named
## @panics if the triple's architecture is another, whose ABI name must be
##   added here (`armeabi-v7a`, `x86`)
export android_abi(triple: String): String {
    var arch = triple.split("-")[0];
    assert(arch == "aarch64" or arch == "x86_64", $"no Android ABI name for '{arch}': add it to android_abi");
    return arch == "aarch64" ? "arm64-v8a" : arch;
}

## The `AndroidManifest.xml` of the Android library `name`: the package
## `pepper.<name>`, for the API level Pepper's Android code needs
## (`link.DEFAULT_ANDROID_API`).
##
## @param name the library's name
## @returns the manifest, as XML
export aar_manifest(name: String): String {
    return $"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\" package=\"pepper.{name}\">\n    <uses-sdk android:minSdkVersion=\"{link.DEFAULT_ANDROID_API}\" />\n</manifest>\n";
}

## A zip archive of `entries` (each a name and its bytes; a name ending in
## `/` is a folder), stored without compression and dated 1980-01-01, so the
## same entries always give the same bytes.
##
## @param entries the archive's files and folders, in order
## @returns the archive's bytes
export zip_stored(entries: (String, u8[])[]): u8[] {
    # shortcut: no zip64, so under 4 GiB and 65535 entries (an `.aar` is a
    # few MB); write zip64 records if a library ever nears that.
    var out = Array<u8>();
    var central = Array<u8>();
    for (var (name, data) in entries) {
        var crc = compress.Crc32.of(data) as ulong;
        var offset = out.count;
        _put_u32(out, 0x04034b50, false);
        _zip_header(out, name, data.count, crc);
        out.append_all(name.bytes());
        out.append_all(data);
        _put_u32(central, 0x02014b50, false);
        _put_u16(central, 20);
        _zip_header(central, name, data.count, crc);
        # No comment, disk 0, no internal attributes; MS-DOS's directory bit.
        _put_u16(central, 0);
        _put_u16(central, 0);
        _put_u16(central, 0);
        _put_u32(central, name.ends_with("/") ? 0x10 : 0, false);
        _put_u32(central, offset, false);
        central.append_all(name.bytes());
    }
    var directory = out.count;
    out.append_all(central);
    _put_u32(out, 0x06054b50, false);
    _put_u16(out, 0);
    _put_u16(out, 0);
    _put_u16(out, entries.count);
    _put_u16(out, entries.count);
    _put_u32(out, central.count, false);
    _put_u32(out, directory, false);
    _put_u16(out, 0);
    return out;
}

# The fields a zip's local and central headers share, from the version
# needed to the extra field's length: stored, at 00:00 on 1980-01-01.
_zip_header(out: u8[], name: String, size: ulong, crc: ulong) {
    _put_u16(out, 20);
    _put_u16(out, 0);
    _put_u16(out, 0);
    _put_u16(out, 0);
    _put_u16(out, 0x21);
    _put_u32(out, crc, false);
    _put_u32(out, size, false);
    _put_u32(out, size, false);
    _put_u16(out, name.size);
    _put_u16(out, 0);
}
