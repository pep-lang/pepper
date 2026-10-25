## `--lib xcframework` and `--lib swift-package`: an iOS library an Xcode
## project or SwiftPM adds as one dependency (see the book's "iOS and
## Android").
##
## The compiler builds the program's static library once per iOS target, by
## running itself with `--lib static --target <triple>`, then lays out the
## `.xcframework` by hand, so no Xcode is needed: a slice for devices
## (`ios-arm64`) and one for the simulator (`ios-arm64_x86_64-simulator`),
## whose two archives are merged into one universal file (`universal_file`,
## as `lipo -create` writes it), each with the header and a
## `module.modulemap` so Swift can `import` it, and the `Info.plist` that
## lists the slices. A Swift package is a folder holding the `.xcframework`
## and a `Package.swift` whose `binaryTarget` names it.

import [Directory, File, Path] from io;
import process;
import "library";

## A slice of the `.xcframework`: its library identifier, the triples whose
## archives it holds, and their Mach-O architectures.
struct _Slice {
    var identifier: String;
    var triples: String[];
    var architectures: String[];
    var simulator: bool;

    construct(identifier: String, triples: String[], architectures: String[], simulator: bool) {
        this.identifier = identifier;
        this.triples = triples;
        this.architectures = architectures;
        this.simulator = simulator;
    }
}

# The iOS slices: the device's, and the simulator's on Apple silicon and
# Intel Macs.
_slices(): _Slice[] {
    return [
        _Slice("ios-arm64", ["aarch64-apple-ios"], ["arm64"], false),
        _Slice(
            "ios-arm64_x86_64-simulator",
            ["aarch64-apple-ios-simulator", "x86_64-apple-ios-simulator"],
            ["arm64", "x86_64"],
            true
        ),
    ];
}

## Builds the library of this build's program as an `.xcframework` named
## `name` at `output`, whose module Swift imports is `name`; or with
## `package` a Swift package folder at `output` holding `Package.swift`,
## `C<name>.xcframework`, whose module is `C<name>`, and the Swift module
## `name`, the wrappers `--bindings swift` writes, in `Sources/<name>`.
## Each target's static library is built by `compiler`, side by side, with
## this build's `arguments` and `--lib static --target <triple>`, into
## `build`.
##
## @param compiler the compiler to run for each target
## @param arguments this build's command line, the program first
## @param output the `.xcframework`, or the package's folder
## @param name the library's name, which Swift imports
## @param build the build folder; each target builds in a folder of its own there
## @param package whether to write a Swift package around the `.xcframework`
## @returns nothing, or why it cannot be built
export build_xcframework(
    compiler: Path, arguments: String[], output: Path, name: String, build: Path, package: bool
): Result<void, String> {
    var triples = Array<String>();
    for (var slice in _slices()) {
        triples.append_all(slice.triples);
    }
    var options = ["--lib", "static"];
    if (package) {
        options.append_all(["--bindings", "swift"]);
    }
    var built = build_for_targets(compiler, arguments, options, triples, build, $"lib{name}.a");
    if (built.is_err()) {
        return built;
    }
    var module = package ? swift_c_module(name) : name;
    var framework = package ? output.join(Path($"{module}.xcframework")) : output;
    # Stale slices would otherwise stay listed beside the new ones.
    if (framework.exists()) {
        var removed = Directory.remove_all(framework);
        if (removed.is_err()) {
            return Result<void, String>.err($"cannot remove {framework}: {removed.error().message}");
        }
    }
    for (var slice in _slices()) {
        var headers = framework.join(Path(slice.identifier)).join(Path("Headers"));
        var made = Directory.create_all(headers);
        if (made.is_err()) {
            return Result<void, String>.err($"cannot create {headers}: {made.error().message}");
        }
        var archives = Array<u8[]>();
        for (var triple in slice.triples) {
            var read = File.read_bytes(_archive(build, triple, name));
            if (read.is_err()) {
                return Result<void, String>.err($"cannot read {_archive(build, triple, name)}: {read.error().message}");
            }
            archives.append(read.value());
        }
        var library = archives.count == 1 ? archives[0] : universal_file(archives, slice.architectures);
        var slice_folder = framework.join(Path(slice.identifier));
        var archive = slice_folder.join(Path($"lib{name}.a"));
        var written = Result<void, String>.ok();
        if (File.write_bytes(archive, library).is_err()) {
            written = Result<void, String>.err($"cannot write {archive}");
        } else {
            # The header `--lib static` wrote beside the archive.
            var header = build.join(Path(slice.triples[0])).join(Path($"{name}.h"));
            var copied = File.copy(header, headers.join(Path($"{name}.h")));
            if (copied.is_err()) {
                return Result<void, String>.err($"cannot copy {header}: {copied.error().message}");
            }
            written = _write_text(
                headers.join(Path("module.modulemap")), $"module {module} {{\n    header \"{name}.h\"\n    export *\n}}\n"
            );
        }
        if (written.is_err()) {
            return written;
        }
    }
    var listed = _write_text(framework.join(Path("Info.plist")), xcframework_info_plist(name));
    if (listed.is_err() or !package) {
        return listed;
    }
    var sources = output.join(Path("Sources")).join(Path(name));
    var made = Directory.create_all(sources);
    if (made.is_err()) {
        return Result<void, String>.err($"cannot create {sources}: {made.error().message}");
    }
    # The wrappers every target wrote are the same: take the first's.
    var swift = build.join(Path(triples[0])).join(Path($"{name}.swift"));
    var copied = File.copy(swift, sources.join(Path($"{name}.swift")));
    if (copied.is_err()) {
        return Result<void, String>.err($"cannot copy {swift}: {copied.error().message}");
    }
    return _write_text(output.join(Path("Package.swift")), swift_package_manifest(name));
}

## Builds this build's program once for each of `triples`, side by side, by
## running `compiler` with `arguments`, `options` (`--lib <kind>`, and any
## `--bindings`) and `--target <triple>`, each into `<build>/<triple>/<file>`
## with that folder as its build folder.
## `--lib aar` (`aar.pep`) builds its shared libraries this way too.
##
## @param compiler the compiler to run for each target
## @param arguments this build's command line, the program first
## @param options the options that choose what each target builds
## @param triples the targets
## @param build the build folder
## @param file the library's file name in each target's folder
## @returns nothing, or why one could not be built: empty when the
##   compiler printed why itself
export build_for_targets(
    compiler: Path, arguments: String[], options: String[], triples: String[], build: Path, file: String
): Result<void, String> {
    var passed = Array<String>();
    for (var i in 1..arguments.count) {
        passed.append(arguments[i]);
    }
    var children = Array<process.Child>();
    for (var triple in triples) {
        var folder = build.join(Path(triple));
        var started = process
            .Command(compiler.to_string())
            .arguments(passed)
            .arguments(options)
            .arguments(
                [
                    "--target",
                    triple,
                    "-o",
                    folder.join(Path(file)).to_string(),
                    "--build",
                    folder.to_string()
                ]
            )
            .stdout(process.Stream.Inherit)
            .stderr(process.Stream.Inherit)
            .spawn();
        if (started.is_err()) {
            return Result<void, String>.err($"cannot run {compiler}: {started.error().message}");
        }
        children.append(started.value());
    }
    bool failed = false;
    for (var child in children) {
        var status = child.wait();
        failed = failed or status.is_err() or !status.value().success();
    }
    if (failed) {
        # Each child printed why.
        return Result<void, String>.err("");
    }
    return Result<void, String>.ok();
}

## The name of the C module Swift bindings import: `C<name>`, so the Swift
## module can be `<name>`.
##
## @param name the library's name
## @returns the C module's name
export swift_c_module(name: String): String {
    return "C" + name;
}

## Whether `name` can name a Swift module and a C header: letters, digits
## and `_`, not starting with a digit.
##
## @param name the library's name
## @returns true when it can
export is_module_name(name: String): bool {
    var bytes = name.bytes();
    for (var i in 0..bytes.count) {
        var c = bytes[i];
        bool letter = (c >= 'a' as u8 and c <= 'z' as u8) or (c >= 'A' as u8 and c <= 'Z' as u8) or c == '_' as u8;
        bool digit = c >= '0' as u8 and c <= '9' as u8;
        if (!letter and !(digit and i > 0)) {
            return false;
        }
    }
    return !bytes.is_empty;
}

## The `Info.plist` of the iOS `.xcframework` of the library `name`: its
## device and simulator slices, each `lib<name>.a` with a `Headers` folder.
##
## @param name the library's name
## @returns the property list, as XML
export xcframework_info_plist(name: String): String {
    var libraries = "";
    for (var slice in _slices()) {
        var architectures = "";
        for (var architecture in slice.architectures) {
            architectures += $"\t\t\t\t<string>{architecture}</string>\n";
        }
        var variant = slice.simulator ?
            "\t\t\t<key>SupportedPlatformVariant</key>\n\t\t\t<string>simulator</string>\n" :
            "";
        libraries += $"\t\t<dict>\n\t\t\t<key>HeadersPath</key>\n\t\t\t<string>Headers</string>\n\t\t\t<key>LibraryIdentifier</key>\n\t\t\t<string>{slice.identifier}</string>\n\t\t\t<key>LibraryPath</key>\n\t\t\t<string>lib{name}.a</string>\n\t\t\t<key>SupportedArchitectures</key>\n\t\t\t<array>\n{architectures}\t\t\t</array>\n\t\t\t<key>SupportedPlatform</key>\n\t\t\t<string>ios</string>\n{variant}\t\t</dict>\n";
    }
    return $"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>AvailableLibraries</key>\n\t<array>\n{libraries}\t</array>\n\t<key>CFBundlePackageType</key>\n\t<string>XFWK</string>\n\t<key>XCFrameworkFormatVersion</key>\n\t<string>1.0</string>\n</dict>\n</plist>\n";
}

## The `Package.swift` of a Swift package whose library product `name` is
## the Swift target `name` (the wrappers in `Sources/<name>`), over the
## binary target `C<name>`, the `C<name>.xcframework` beside it, for iOS 15
## and later (Pepper's oldest iOS).
##
## @param name the library's name
## @returns the manifest's source
export swift_package_manifest(name: String): String {
    var module = swift_c_module(name);
    return $"// swift-tools-version:5.5\nimport PackageDescription\n\nlet package = Package(\n    name: \"{name}\",\n    platforms: [.iOS(.v15)],\n    products: [.library(name: \"{name}\", targets: [\"{name}\"])],\n    targets: [\n        .binaryTarget(name: \"{module}\", path: \"{module}.xcframework\"),\n        .target(name: \"{name}\", dependencies: [\"{module}\"]),\n    ]\n)\n";
}

## A universal (fat) Mach-O file holding `files`, one for each of
## `architectures` (`arm64`, `x86_64`), as `lipo -create` writes it: the
## big-endian header listing each file's CPU type and where it starts, then
## the files, each 16 KiB aligned.
##
## @param files the thin files: archives or Mach-O objects
## @param architectures each file's architecture
## @returns the universal file's bytes
## @panics if an architecture is neither `arm64` nor `x86_64`, or the counts differ
export universal_file(files: u8[][], architectures: String[]): u8[] {
    assert(files.count == architectures.count, "one architecture for each file");
    var out = Array<u8>();
    _put_u32(out, 0xcafebabe, true);
    _put_u32(out, files.count, true);
    var offset = _aligned(8 + 20 * files.count);
    for (var i in 0..files.count) {
        assert(architectures[i] == "arm64" or architectures[i] == "x86_64", "arm64 or x86_64");
        # CPU_TYPE_ARM64 with CPU_SUBTYPE_ARM64_ALL, or CPU_TYPE_X86_64 with
        # CPU_SUBTYPE_X86_64_ALL.
        bool arm = architectures[i] == "arm64";
        _put_u32(out, arm ? 0x0100000c : 0x01000007, true);
        _put_u32(out, arm ? 0 : 3, true);
        _put_u32(out, offset, true);
        _put_u32(out, files[i].count, true);
        _put_u32(out, _ALIGN_POWER, true);
        offset = _aligned(offset + files[i].count);
    }
    for (var file in files) {
        _pad(out, 1 << _ALIGN_POWER, 0);
        out.append_all(file);
    }
    return out;
}

# A universal file's thin files start at multiples of 2^14 bytes, as
# `lipo` aligns them for arm64.
const _ALIGN_POWER: ulong = 14;

# `offset` rounded up to the alignment of a universal file's thin files.
_aligned(offset: ulong): ulong {
    var align: ulong = 1 << _ALIGN_POWER;
    return (offset + align - 1) / align * align;
}

# Where the static library for `triple` is built.
_archive(build: Path, triple: String, name: String): Path {
    return build.join(Path(triple)).join(Path($"lib{name}.a"));
}

# Writes `content` to `path`.
_write_text(path: Path, content: String): Result<void, String> {
    var written = File.write_text(path, content);
    if (written.is_err()) {
        return Result<void, String>.err($"cannot write {path}: {written.error().message}");
    }
    return Result<void, String>.ok();
}
