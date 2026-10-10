# pep-install's commands against a Pepper home in a test folder: versions
# and how a folder's toolchain is chosen, the releases list, unpacking,
# and installing from a server on loopback that stands in for GitHub.
# Run with `-I tools`.

import archive;
import async;
import compress;
import digest;
import [Directory, File, Path] from io;
import io;
import [serve_folder] from tool_testing.server;
import tls;
import toolchain;
import "commands";
import "releases";
import "zip";

[Test]
reads_versions_and_the_versions_a_command_names() {
    expect_equal(toolchain.parse_version("0.3.1").value().to_string(), "0.3.1");
    expect_equal(toolchain.parse_version("v10.0.2").value().to_string(), "10.0.2");
    expect_true(toolchain.parse_version("0.3").is_empty());
    expect_true(toolchain.parse_version("0.03.1").is_empty());
    expect_true(toolchain.parse_version("vsix-0.3.0").is_empty());
    expect_true(toolchain.parse_version("0.3.0").value().compare(toolchain.parse_version("0.10.0").value()) < 0);

    var minor = toolchain.parse_spec("0.3").value();
    expect_true(minor.matches(toolchain.Version(0, 3, 7)));
    expect_false(minor.matches(toolchain.Version(0, 4, 0)));
    expect_false(minor.is_exact);
    expect_equal(toolchain.parse_spec("latest").value().to_string(), "latest");
    expect_true(toolchain.parse_spec("latest").value().matches(toolchain.Version(9, 9, 9)));
    expect_true(toolchain.parse_spec("0.3.0.1").is_empty());
    expect_true(toolchain.parse_spec("nightly").is_empty());

    var versions = [toolchain.Version(0, 2, 1), toolchain.Version(0, 3, 2), toolchain.Version(0, 3, 10)];
    expect_equal(toolchain.newest_match(versions, minor).value().to_string(), "0.3.10");
    expect_true(toolchain.newest_match(versions, toolchain.parse_spec("1").value()).is_empty());
}

[Test]
reads_prerelease_versions() {
    var dev = toolchain.parse_version("v0.4.0-dev").value();
    expect_equal(dev.prerelease, "dev");
    expect_equal(dev.to_string(), "0.4.0-dev");
    expect_equal(toolchain.parse_version("0.4.0-rc.1").value().to_string(), "0.4.0-rc.1");
    expect_true(toolchain.parse_version("0.4.0-").is_empty());
    expect_true(toolchain.parse_version("0.4.0-dev build").is_empty());
    expect_true(toolchain.parse_spec("0.4-dev").is_empty());

    # A prerelease sorts after the release before it and before its own.
    expect_true(toolchain.Version(0, 3, 9).compare(dev) < 0);
    expect_true(dev.compare(toolchain.Version(0, 4, 0)) < 0);
    expect_true(dev.compare(toolchain.parse_version("0.4.0-dev").value()) == 0);

    # Only a spec naming the prerelease picks it.
    var versions = [toolchain.Version(0, 3, 0), dev];
    expect_equal(toolchain.newest_match(versions, toolchain.parse_spec("latest").value()).value().to_string(), "0.3.0");
    expect_true(toolchain.newest_match(versions, toolchain.parse_spec("0.4").value()).is_empty());
    expect_true(toolchain.newest_match(versions, toolchain.parse_spec("0.4.0").value()).is_empty());
    var named = toolchain.parse_spec("0.4.0-dev").value();
    expect_true(named.is_exact);
    expect_equal(named.to_string(), "0.4.0-dev");
    expect_equal(toolchain.newest_match(versions, named).value().to_string(), "0.4.0-dev");
}

# Makes a toolchain folder that `Home.installed` counts.
fake_toolchain(home: toolchain.Home, version: String) {
    var bin = home.toolchain(toolchain.parse_version(version).value()).join("bin");
    Directory.create_all(bin).value();
    var compiler = bin.join("pep-build" + toolchain.executable_suffix());
    File.write_text(compiler, "").value();
    compiler.set_executable(true);
}

[Test]
chooses_a_folders_toolchain_in_order() {
    var folder = TempFolder("chooses_a_folders_toolchain_in_order");
    var home = toolchain.Home(folder.path.join("home"));
    fake_toolchain(home, "0.2.1");
    fake_toolchain(home, "0.3.0");
    fake_toolchain(home, "0.3.2");
    # A folder without a toolchain folder holding pep-build is not one.
    Directory.create_all(home.toolchains.join("0.4.0")).value();
    expect_equal(home.installed().count, 3);
    expect_equal(home.installed()[0].to_string(), "0.3.2");

    var project = folder.path.join("app");
    var source = project.join("src");
    Directory.create_all(source).value();
    expect_true(toolchain.choose_toolchain(home, "", "", source).value().is_empty());

    home.set_default(toolchain.Version(0, 2, 1)).value();
    var by_default = toolchain.choose_toolchain(home, "", "", source).value().value();
    expect_equal(by_default.version.value().to_string(), "0.2.1");
    expect_equal(by_default.reason(), "the default");

    File.write_text(project.join("pep.toml"), "[package]\nname = \"app\"\ntoolchain = \"0.3\"\n").value();
    var pinned = toolchain.choose_toolchain(home, "", "", source).value().value();
    expect_equal(pinned.version.value().to_string(), "0.3.2");
    expect_equal(pinned.reason(), $"pinned by {project.join("pep.toml").to_string()}");

    var environment = toolchain.choose_toolchain(home, "", "0.3.0", source).value().value();
    expect_equal(environment.version.value().to_string(), "0.3.0");
    expect_equal(environment.reason(), "named by PEPPER_TOOLCHAIN");

    var named = toolchain.choose_toolchain(home, "0.2", "0.3.0", source).value().value();
    expect_equal(named.version.value().to_string(), "0.2.1");
    expect_equal(named.reason(), "named by 'pepper +0.2'");

    var missing = toolchain.choose_toolchain(home, "0.9", "", source).value().value();
    expect_true(missing.version.is_empty());
    expect_true(
        which_toolchain(
            home, Optional<toolchain.Choice>.Value(missing)
        ).error().message.contains("pepper install add 0.9")
    );
    expect_true(toolchain.choose_toolchain(home, "nightly", "", source).is_err());

    File.write_text(project.join("pep.toml"), "[package]\nname = \"app\"\ntoolchain = 3\n").value();
    expect_true(toolchain.choose_toolchain(home, "", "", source).is_err());

    expect_equal(installed_list(home, Optional<toolchain.Choice>.Value(by_default)), "0.3.2\n0.3.0\n0.2.1 (default)\n");
    var listed = installed_list(home, Optional<toolchain.Choice>.Value(pinned));
    expect_equal(listed, $"0.3.2 (in use here, {pinned.reason()})\n0.3.0\n0.2.1 (default)\n");
}

[Test]
uses_and_removes_installed_toolchains() {
    var folder = TempFolder("uses_and_removes_installed_toolchains");
    var home = toolchain.Home(folder.path);
    fake_toolchain(home, "0.2.1");
    fake_toolchain(home, "0.3.0");
    fake_toolchain(home, "0.3.2");
    expect_equal(use_toolchain(home, toolchain.parse_spec("0.3").value()).value(), "0.3.2 is the default\n");
    expect_equal(home.default_version().value().to_string(), "0.3.2");
    expect_true(use_toolchain(home, toolchain.parse_spec("0.4").value()).is_err());

    expect_true(remove_toolchain(home, toolchain.parse_spec("0.3").value()).error().message.contains("0.3.2, 0.3.0"));
    expect_true(
        remove_toolchain(home, toolchain.parse_spec("0.3.2").value()).error().message.contains("is the default")
    );
    expect_equal(remove_toolchain(home, toolchain.parse_spec("0.2.1").value()).value(), "removed 0.2.1\n");
    expect_false(home.toolchain(toolchain.Version(0, 2, 1)).exists());
    expect_equal(home.installed().count, 2);
}

[Test]
reads_the_releases_for_a_machine() {
    var listed = "["
        + github_release("v0.2.1", false, ["pepper-0.2.1-linux-x64.tar.gz", "pepper-0.2.1-linux-x64.tar.gz.sha256"])
        + ","
        + github_release("vsix-0.3.0", false, ["pepper-language-0.3.0.vsix"])
        + ","
        + github_release(
            "v0.4.0-rc.1", true, ["pepper-0.4.0-rc.1-linux-x64.tar.gz", "pepper-0.4.0-rc.1-linux-x64.tar.gz.sha256"]
        )
        + ","
        + github_release("v0.5.0", true, ["pepper-0.5.0-linux-x64.tar.gz", "pepper-0.5.0-linux-x64.tar.gz.sha256"])
        + ","
        + github_release(
            "v0.3.0",
            false,
            [
                "pepper-0.3.0-linux-x64.tar.gz",
                "pepper-0.3.0-linux-x64.tar.gz.sha256",
                "pepper-0.3.0-windows-x64.zip",
                "pepper-0.3.0-windows-x64.zip.sha256"
            ]
        )
        + ","
        + github_release("v0.2.0", false, ["pepper-0.2.0-linux-x64.tar.gz"])
        + "]";
    # The prerelease whose tag names one is listed; a prerelease tagged as
    # a release (v0.5.0) is not.
    var linux = parse_releases(listed, "linux-x64").value();
    expect_equal(linux.count, 3);
    expect_equal(linux[0].version.to_string(), "0.4.0-rc.1");
    expect_equal(linux[0].archive_name, "pepper-0.4.0-rc.1-linux-x64.tar.gz");
    expect_equal(linux[1].version.to_string(), "0.3.0");
    expect_equal(linux[1].archive_name, "pepper-0.3.0-linux-x64.tar.gz");
    expect_equal(linux[1].archive_url, "https://example.com/assets/pepper-0.3.0-linux-x64.tar.gz");
    expect_equal(linux[1].checksum_url, "https://example.com/assets/pepper-0.3.0-linux-x64.tar.gz.sha256");
    expect_equal(linux[2].version.to_string(), "0.2.1");
    var windows = parse_releases(listed, "windows-x64").value();
    expect_equal(windows.count, 1);
    expect_equal(windows[0].archive_name, "pepper-0.3.0-windows-x64.zip");
    expect_true(parse_releases("{}", "linux-x64").is_err());
}

# A release as GitHub's API lists it, with `assets` served from
# `https://example.com/assets/`.
github_release(tag: String, prerelease: bool, assets: Array<String>): String {
    return github_release_at("https://example.com/assets/", tag, prerelease, assets);
}

github_release_at(base: String, tag: String, prerelease: bool, assets: Array<String>): String {
    var listed = Array<String>();
    for (var name in assets) {
        listed.append($"{{\"name\": \"{name}\", \"url\": \"{base}{name}\", \"size\": 1}}");
    }
    return $"{{\"tag_name\": \"{tag}\", \"draft\": false, \"prerelease\": {prerelease}, \"assets\": [{", ".join(listed)}]}}";
}

[Test]
unzips_a_windows_release() {
    var folder = TempFolder("unzips_a_windows_release");
    var data = File.read_bytes(Path("pep-install/testdata/toolchain.zip")).value();
    unzip(data, folder.path, 1).value();
    expect_equal(File.read_to_string(folder.path.join("bin").join("pep-build.exe")).value().size, 450);
    expect_equal(File.read_to_string(folder.path.join("runtime").join("core.pep")).value(), "# runtime\n");

    var unsafe = File.read_bytes(Path("pep-install/testdata/unsafe.zip")).value();
    expect_true(unzip(unsafe, folder.path.join("unsafe"), 1).error().message.contains("unsafe path"));
    expect_false(folder.path.join("escaped.txt").exists());
    expect_true(unzip([1, 2, 3], folder.path, 1).is_err());
}

# A release archive of the toolchain `version`, as release-build.sh packs
# one: a folder holding bin/pep-build and the runtime.
toolchain_archive(version: String): u8[] {
    var packed = io.ByteWriter();
    var gzip = compress.CompressWriter(packed, compress.Format.Gzip);
    var tar = archive.TarWriter(gzip);
    var top = $"pepper-{version}-linux-x64/";
    tar.append_directory(top).value();
    tar.append_file(top + "bin/pep-build" + toolchain.executable_suffix(), "compiler".bytes(), mode = 493).value();
    tar.append_file(top + "runtime/core.pep", "# runtime\n".bytes()).value();
    for (var name in ["pepper", "pep-install"]) {
        tar.append_file(
            top + "bin/" + name + toolchain.executable_suffix(), $"{name} {version}".bytes(), mode = 493
        ).value();
    }
    tar.finish().value();
    gzip.finish().value();
    return packed.bytes;
}

# Puts the release `version` in `root`, an archive and its `.sha256`
# (`checksum` instead of the right one when it is not empty), and returns
# its entry for the releases list.
publish(root: Path, base: String, version: String, checksum: String): String {
    var name = $"pepper-{version}-linux-x64.tar.gz";
    var data = toolchain_archive(version);
    File.write_bytes(root.join(name), data).value();
    var sha256 = checksum.is_empty ? digest.to_hex(digest.sha256(data)) : checksum;
    File.write_text(root.join(name + ".sha256"), $"{sha256}  {name}\n").value();
    return github_release_at(base, "v" + version, false, [name, name + ".sha256"]);
}

[Test]
installs_and_updates_from_the_releases() {
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    var folder = TempFolder("installs_and_updates_from_the_releases");
    var served = folder.path.join("served");
    Directory.create_all(served).value();
    var home = toolchain.Home(folder.path.join("home"));
    async.run(
        () => {
            var base = serve_folder(served);
            var entries = [
                publish(served, base, "0.3.1", ""),
                publish(served, base, "0.3.0", ""),
                publish(served, base, "0.2.1", "")
            ];
            File.write_text(served.join("releases.json"), "[" + ", ".join(entries) + "]").value();
            var releases = fetch_releases(base + "releases.json", "linux-x64").value();
            expect_equal(releases.count, 3);
            expect_equal(available_list(home, releases), "0.3.1\n0.3.0\n0.2.1\n");

            expect_equal(
                add_toolchain(home, releases, toolchain.parse_spec("0.2").value()).value(),
                "installed 0.2.1 and made it the default\n"
            );
            var compiler = home.toolchain_bin(toolchain.Version(0, 2, 1)).join(
                "pep-build" + toolchain.executable_suffix()
            );
            expect_equal(File.read_to_string(compiler).value(), "compiler");
            expect_equal(
                File.read_to_string(
                    home.toolchain(toolchain.Version(0, 2, 1)).join("runtime").join("core.pep")
                ).value(),
                "# runtime\n"
            );
            expect_equal(
                add_toolchain(home, releases, toolchain.parse_spec("0.3.0").value()).value(),
                "installed 0.3.0; make it the default with 'pepper install use 0.3.0'\n"
            );
            expect_equal(
                add_toolchain(home, releases, toolchain.parse_spec("0.3.0").value()).value(),
                "0.3.0 is already installed\n"
            );
            expect_true(
                add_toolchain(
                    home, releases, toolchain.parse_spec("0.5").value()
                ).error().message.contains("no release is 0.5")
            );
            expect_equal(available_list(home, releases), "0.3.1\n0.3.0 (installed)\n0.2.1 (installed)\n");
            expect_equal(home.default_version().value().to_string(), "0.2.1");

            # update also brings the home's pepper and pep-install up to date.
            var entry_point = home.bin.join("pepper" + toolchain.executable_suffix());
            expect_equal(
                update_toolchain(home, releases).value(),
                $"installed 0.3.1 and made it the default\nupdated pepper and pep-install in {home.bin.to_string()}\n"
            );
            expect_equal(File.read_to_string(entry_point).value(), "pepper 0.3.1");
            expect_false(Path(entry_point.to_string() + ".old").exists());
            expect_equal(
                update_toolchain(home, releases).value(), "0.3.1, the newest release, is installed and the default\n"
            );
            File.write_text(home.bin.join("pep-install" + toolchain.executable_suffix()), "pep-install 0.2.1").value();
            expect_equal(
                update_toolchain(home, releases).value(),
                $"0.3.1, the newest release, is installed and the default\nupdated pep-install in {home.bin.to_string()}\n"
            );
            expect_equal(home.installed().count, 3);

            # A download that does not match its .sha256 installs nothing.
            var bad = publish(
                served, base, "0.4.0", "0000000000000000000000000000000000000000000000000000000000000000"
            );
            File.write_text(served.join("releases.json"), "[" + bad + "]").value();
            var tampered = fetch_releases(base + "releases.json", "linux-x64").value();
            expect_true(
                add_toolchain(
                    home, tampered, toolchain.parse_spec("0.4.0").value()
                ).error().message.contains("does not match its .sha256")
            );
            expect_false(home.toolchain(toolchain.Version(0, 4, 0)).exists());
            expect_false(Path(home.toolchain(toolchain.Version(0, 4, 0)).to_string() + ".partial").exists());
            expect_equal(home.installed().count, 3);
        }
    );
}
