# Compiling for another platform (`--target`): the triples the compiler
# accepts, `[Target(...)]` selecting the target's code, the target's
# machine in the IR and objects, and the link driver's options for it, as
# the compiler has always had them.

import compiler.codegen;
import compiler.driver;
import [Directory, File, Path] from io;
import compiler.link;
import compiler.sema;
import [TempFolder] from testing;

# `triple` parsed, which must succeed.
_parse(triple: String): link.Target {
    var target = link.Target.parse(triple);
    if (target.is_err()) {
        print(target.error());
    }
    expect_true(target.is_ok());
    return target.value();
}

[Test]
reads_each_supported_triple() {
    for (var triple in link.supported_triples()) {
        expect_true(link.Target.parse(triple).is_ok());
    }
    var arm = _parse("aarch64-unknown-linux-gnu");
    expect_equal(arm.os, "linux");
    expect_equal(arm.arch, "aarch64");
    expect_equal(arm.triple, "aarch64-unknown-linux-gnu");
    var mac = _parse("arm64-apple-macosx14.0");
    expect_equal(mac.os, "macos");
    expect_equal(mac.arch, "aarch64");
    expect_equal(mac.triple, "arm64-apple-macosx14.0");
    expect_true(mac.is_apple());
    var windows = _parse("amd64-pc-windows-msvc");
    expect_equal(windows.os, "windows");
    expect_equal(windows.arch, "x86_64");
}

[Test]
names_webassembly_and_the_mobile_platforms_as_clang_does() {
    var wasm = _parse("wasm32-wasi");
    expect_equal(wasm.os, "wasi");
    expect_equal(wasm.arch, "wasm32");
    expect_equal(wasm.triple, "wasm32-wasip1");
    expect_equal(_parse("aarch64-apple-ios").triple, "aarch64-apple-ios15.0");
    var simulator = _parse("aarch64-apple-ios17.0-sim");
    expect_equal(simulator.triple, "aarch64-apple-ios17.0-simulator");
    expect_equal(simulator.platform_triple(), "aarch64-apple-ios-simulator");
    # No iPhone is x86_64: its iOS is the simulator's.
    expect_equal(_parse("x86_64-apple-ios").triple, "x86_64-apple-ios15.0-simulator");
    var android = _parse("aarch64-unknown-linux-android33");
    expect_equal(android.os, "android");
    expect_equal(android.triple, "aarch64-linux-android33");
    expect_equal(android.platform_triple(), "aarch64-linux-android");
    expect_equal(_parse("x86_64-linux-android").triple, "x86_64-linux-android30");
}

[Test]
rejects_a_triple_it_does_not_compile_for() {
    var risc = link.Target.parse("riscv64-unknown-linux-gnu");
    expect_true(risc.is_err());
    expect_true(
        risc.error().starts_with(
            "unsupported target 'riscv64-unknown-linux-gnu'; expected one of: x86_64-unknown-linux-gnu"
        )
    );
    expect_true(link.Target.parse("x86_64-unknown-linux-musl").is_err());
    expect_true(link.Target.parse("aarch64-apple-ios-macabi").is_err());
    expect_true(link.Target.parse("aarch64-linux-android29").error().contains("API level 30 or later"));
}

[Test]
names_each_system_root_variable_without_the_os_version() {
    expect_equal(driver.sysroot_variable("aarch64-apple-darwin"), "PEPPER_SYSROOT_AARCH64_APPLE_DARWIN");
    expect_equal(driver.sysroot_variable("arm64-apple-macosx14.0"), "PEPPER_SYSROOT_ARM64_APPLE_MACOSX14_0");
    var root = driver.effective_sysroot(_parse("aarch64-apple-darwin"), Optional<Path>.Value(Path("/sdk")));
    expect_equal(root.value().to_string(), "/sdk");
    expect_false(driver.effective_sysroot(link.Target(), Optional<Path>.Empty).is_value());
}

# The LLVM IR of `source`, a program without the runtime, compiled for
# `target`.
_ir(source: String, target: link.Target): String {
    var folder = TempFolder("target_ir");
    var file = folder.path.join(Path("main.pep"));
    File.write_text(file, source);
    var setup = link.Setup();
    setup.runtime = false;
    setup.target = target;
    var program = link.load_program(file, setup);
    expect_true(program.is_ok());
    var module = sema.merge(program.value());
    expect_true(module.is_ok());
    var state = sema.run_passes(module.value(), program.value().target, program.value().sources());
    expect_true(state.is_ok());
    var namespaces = Array<String>();
    for (var f in program.value().files) {
        namespaces.append(f.namespace);
    }
    var ir = codegen.generate_ir(module.value(), state.value(), namespaces, "main");
    expect_true(ir.is_ok());
    return ir.value();
}

const _BY_PLATFORM = "[Target(Arch(aarch64))]\nwhich(): int {\n    return 64;\n}\n[Target(Arch(x64))]\nwhich(): int {\n    return 86;\n}\n[Target(Arch(wasm32))]\nwhich(): int {\n    return 32;\n}\n[Target(OS(Windows))]\nsystem(): int {\n    return 1;\n}\n[Target(!OS(Windows))]\nsystem(): int {\n    return 2;\n}\nmain(): int {\n    return which() + system();\n}\n";

[Test]
selects_and_generates_the_targets_code() {
    var arm = _ir(_BY_PLATFORM, _parse("aarch64-unknown-linux-gnu"));
    expect_true(arm.contains("target triple = \"aarch64-unknown-linux-gnu\""));
    expect_true(arm.contains("store i32 64, ptr %retval"));
    expect_false(arm.contains("store i32 86, ptr %retval"));
    expect_true(arm.contains("store i32 2, ptr %retval"));
    var windows = _ir(_BY_PLATFORM, _parse("x86_64-pc-windows-msvc"));
    expect_true(windows.contains("target triple = \"x86_64-pc-windows-msvc\""));
    expect_true(windows.contains("store i32 86, ptr %retval"));
    expect_true(windows.contains("store i32 1, ptr %retval"));
    var wasm = _ir(_BY_PLATFORM, _parse("wasm32-wasip1"));
    expect_true(wasm.contains("target triple = \"wasm32-wasip1\""));
    expect_true(wasm.contains("target datalayout = \"e-m:e-p:32:32"));
    expect_true(wasm.contains("store i32 32, ptr %retval"));
}

[Test]
builds_an_arm64_linux_executable_or_says_what_its_link_needs() {
    var folder = TempFolder("target_build");
    var file = folder.path.join(Path("main.pep"));
    File.write_text(file, _BY_PLATFORM);
    var setup = link.Setup();
    setup.runtime = false;
    setup.target = _parse("aarch64-unknown-linux-gnu");
    var program = link.load_program(file, setup);
    expect_true(program.is_ok());
    var output = folder.path.join(Path("main"));
    var options = driver.BuildOptions(output, folder.path.join(Path("build")));
    options.in_process = true;
    var built = driver.build(program.value(), options);
    if (built.is_ok()) {
        # An ELF executable for AArch64 (`e_machine` 183).
        var bytes = File.read_bytes(output).value();
        expect_true(bytes.count > 20);
        expect_equal(bytes[18] as int, 183);
    } else {
        # The object was compiled; the link needs an arm64 system root.
        expect_true(built.error().contains("note: linking for 'aarch64-unknown-linux-gnu'"));
    }
}

[Test]
links_another_platform_with_its_triple_lld_and_system_root() {
    var other = link.Target().os == "linux" ? "aarch64-apple-darwin" : "x86_64-unknown-linux-gnu";
    var target = _parse(other);
    var args = driver.target_arguments(target, Optional<Path>.Value(Path("/sdk")), Optional<Path>.Empty);
    expect_equal(args.count, 3);
    expect_equal(args[0], $"--target={other}");
    expect_equal(args[1], "-fuse-ld=lld");
    expect_equal(args[2], "--sysroot=/sdk");
    # A found lld is named outright, and still announced as lld.
    args = driver.target_arguments(target, Optional<Path>.Empty, Optional<Path>.Value(Path("/usr/bin/ld.lld-20")));
    expect_equal(args[1], "-fuse-ld=lld");
    expect_equal(args[2], "--ld-path=/usr/bin/ld.lld-20");
    var windows = _parse("x86_64-pc-windows-msvc");
    args = driver.target_arguments(windows, Optional<Path>.Value(Path("/xwin")), Optional<Path>.Empty);
    expect_true(args.contains("/winsysroot:/xwin"));
    expect_true(
        driver.cross_link_note(target, Optional<Path>.Empty).contains("pass '--sysroot <dir>' or set PEPPER_SYSROOT_")
    );
    expect_true(driver.target_arguments(link.Target(), Optional<Path>.Empty, Optional<Path>.Empty).is_empty);
}

[Test]
finds_a_windows_system_roots_libraries_in_either_layout() {
    var folder = TempFolder("winsysroot");
    var root = folder.path;
    var vc = root.join(Path("VC")).join(Path("Tools")).join(Path("MSVC"));
    var sdk = root.join(Path("Windows Kits")).join(Path("10")).join(Path("Lib")).join(Path("10.0.22621.0"));
    for (var dir in [
        vc.join(Path("14.29.30133")).join(Path("lib")).join(Path("x64")),
        vc.join(Path("14.40.33807")).join(Path("lib")).join(Path("x64")),
        sdk.join(Path("um")).join(Path("x64")),
        sdk.join(Path("ucrt")).join(Path("x64")),
        root.join(Path("sdk")).join(Path("lib")).join(Path("um")).join(Path("x86_64")),
    ]) {
        Directory.create_all(dir);
    }
    var dirs = driver.windows_library_dirs(root, "x86_64");
    expect_equal(dirs.count, 4);
    expect_equal(dirs[0].to_string(), vc.join(Path("14.40.33807")).join(Path("lib")).join(Path("x64")).to_string());
    expect_equal(dirs[1].to_string(), sdk.join(Path("um")).join(Path("x64")).to_string());
    expect_true(driver.windows_library_dirs(root, "aarch64").is_empty);
}

[Test]
links_webassembly_with_the_wasi_sdk() {
    var folder = TempFolder("wasi_sdk");
    var sysroot = folder.path.join(Path("share")).join(Path("wasi-sysroot"));
    var resources = folder.path.join(Path("lib")).join(Path("clang")).join(Path("19"));
    Directory.create_all(sysroot);
    Directory.create_all(resources);
    for (var dir in [folder.path, sysroot]) {
        var sdk = driver.WasiSdk.locate(Optional<Path>.Value(dir));
        expect_equal(sdk.value().sysroot.to_string(), sysroot.to_string());
        expect_equal(sdk.value().resource_dir.value().to_string(), resources.to_string());
    }
    var args = driver.target_arguments(
        _parse("wasm32-wasi"), Optional<Path>.Value(folder.path), Optional<Path>.Value(Path("/usr/bin/wasm-ld-20"))
    );
    expect_equal(args.count, 4);
    expect_equal(args[0], "--target=wasm32-wasip1");
    expect_equal(args[1], "-fuse-ld=/usr/bin/wasm-ld-20");
    expect_equal(args[2], $"--sysroot={sysroot}");
    expect_equal(args[3], $"-resource-dir={resources}");
    expect_equal(driver.default_system_libraries("wasi")[0], "wasi-emulated-getpid");
}

[Test]
links_android_with_the_ndk_clang_and_ios_like_macos() {
    var folder = TempFolder("ndk");
    var prebuilt = folder.path
        .join(Path("toolchains"))
        .join(Path("llvm"))
        .join(Path("prebuilt"))
        .join(Path("linux-x86_64"));
    var clang = prebuilt.join(Path("bin")).join(Path(link.Target().os == "windows" ? "clang.exe" : "clang"));
    Directory.create_all(prebuilt.join(Path("sysroot")));
    Directory.create_all(prebuilt.join(Path("bin")));
    File.write_text(clang, "");
    for (var dir in [folder.path, prebuilt.join(Path("sysroot"))]) {
        var ndk = driver.AndroidNdk.locate(Optional<Path>.Value(dir));
        expect_equal(ndk.value().clang.to_string(), clang.to_string());
    }
    var android = _parse("aarch64-linux-android");
    var args = driver.target_arguments(android, Optional<Path>.Value(folder.path), Optional<Path>.Empty);
    expect_equal(args.count, 2);
    expect_equal(args[0], "--target=aarch64-linux-android30");
    # bionic keeps threads in libc, and the NDK has no libpthread.
    expect_true(driver.is_built_into_libc("android", "pthread"));
    expect_false(driver.is_built_into_libc("linux", "pthread"));
    var ios = _parse("aarch64-apple-ios-simulator");
    args = driver.target_arguments(ios, Optional<Path>.Value(Path("/sdk")), Optional<Path>.Empty);
    expect_equal(args.count, 4);
    expect_equal(args[0], "--target=aarch64-apple-ios15.0-simulator");
    expect_equal(args[3], "-isysroot/sdk");
    expect_true(driver.cross_link_note(ios, Optional<Path>.Empty).contains("needs an iOS SDK"));
    expect_true(driver.default_system_libraries("ios").is_empty);
}

[Test]
links_libpthread_and_libdl_only_before_glibc_2_34() {
    expect_true(driver.glibc_before_2_34("2.28"));
    expect_true(driver.glibc_before_2_34("2.33"));
    expect_false(driver.glibc_before_2_34("2.34"));
    expect_false(driver.glibc_before_2_34("2.39"));
}

# `[Cold]` (#640) keeps a function out of line: LLVM's `cold` and
# `noinline` on it, and on nothing else.
[Test]
a_cold_function_is_cold_and_never_inlined() {
    var ir = _ir(
        "[Cold]\nslow(n: int): int {\n    return n * 2;\n}\n\nfast(n: int): int {\n    return n + 1;\n}\n\nmain(): int {\n    return slow(fast(1)) - 4;\n}\n",
        link.Target()
    );
    expect_equal(_attributes_of(ir, "slow"), "cold noinline");
    expect_equal(_attributes_of(ir, "fast"), "");
}

# Which of `cold` and `noinline` the IR's definition of `name` carries.
_attributes_of(ir: String, name: String): String {
    var group = "";
    for (var line in ir.split("\n")) {
        if (line.starts_with("define ") and line.contains($"@{name}(")) {
            var hash = line.rfind("#");
            if (hash >= 0) {
                group = line.substr_bytes(hash as ulong, line.size - hash as ulong).split(" ")[0];
            }
        }
    }
    var found = Array<String>();
    for (var line in ir.split("\n")) {
        if (!group.is_empty and line.starts_with($"attributes {group} = ")) {
            for (var attribute in ["cold", "noinline"]) {
                if (line.contains($" {attribute} ")) {
                    found.append(attribute);
                }
            }
        }
    }
    return " ".join(found);
}
