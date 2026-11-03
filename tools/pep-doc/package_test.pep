# `pep-doc package` on a made-up package in a temporary folder: its pages,
# front page and book in process, and `--check` through the pep-doc that
# scripts/pepper-tests.sh built (beside the test program or on the PATH).

import [Path] from io;
import [load_manifest] from compiler.link;
import process;
import [TempFolder] from testing;
import [expect_contains, expect_exit, read_file, run, tool, write_file] from tool_testing;
import [inert_markdown] from "inert";
import "package";
import "reference";

# Writes the package `shapes` into `root`: a module with features, a
# nested module, a dependency of each kind, and the files the reference
# leaves out (tests, examples, another package).
write_package(root: Path) {
    write_file(
        root.join("pep.toml"),
        "[package]\nname = \"shapes\"\nversion = \"1.2.0\"\ndescription = \"Areas and volumes\"\n\n[dependencies]\nsemver = { github = \"Pep-Lang/pepper-semver\", version = \"1\", optional = true }\nlocal = { path = \"../local\" }\n\n[target.'OS(Windows)'.dependencies]\nwin = { codeberg = \"someone/win\", version = \"1\" }\n\n[features]\ndefault = [\"fast\"]\nfast = []\ntls = [\"dep:semver\"]\n"
    );
    write_file(
        root.join("module.pep"),
        "## Shapes: areas and volumes.\n\nexport * from \"area\";\nexport * from shapes.solids;\nexport [JsonValue] from json;\n"
    );
    write_file(
        root.join("area.pep"),
        "## Areas.\n\n## Returns the area of a square.\n##\n## @param side the side\n## @returns the area\nexport square(side: int): int {\n    return side * side;\n}\n\n## Returns one, fast.\n##\n## @returns one\n[BuildOption(\"shapes_fast\")]\nexport quick(): int {\n    return 1;\n}\n\n## A secure thing.\n[Target(BuildOption(shapes_tls) && OS(Linux))]\nexport struct Secure {\n    ## Makes one.\n    [Target(BuildOption(shapes_fast))]\n    construct() {}\n}\n\n## Only without the feature.\n[Target(!BuildOption(shapes_fast) || BuildOption(shapes_tls))]\nexport slow() {}\n\nexport undocumented() {}\n"
    );
    write_file(
        root.join("solids").join("module.pep"),
        "## Solids.\n\n## Returns zero.\n##\n## @returns zero\nexport volume(): int {\n    return 0;\n}\n"
    );
    write_file(root.join("tests").join("helper.pep"), "## A helper.\nexport helper() {}\n");
    write_file(root.join("solids").join("cube_test.pep"), "## A test helper.\nexport cube() {}\n");
    write_file(root.join("examples").join("main.pep"), "## An example.\nexport example() {}\n");
    write_file(root.join("member").join("pep.toml"), "[package]\nname = \"member\"\n");
    write_file(root.join("member").join("module.pep"), "## Another package.\nexport member() {}\n");
}

[Test]
documents_a_package_with_its_features_and_dependencies() {
    var folder = TempFolder("pep_doc_package");
    write_package(folder.path);
    var manifest = load_manifest(folder.path.join("pep.toml"), Array<Path>()).value();
    var pages = package_pages(manifest).value();
    expect_equal(pages.count, 3 as ulong);
    expect_equal(pages[0].file, "module.md");
    expect_equal(pages[0].title, "shapes");
    expect_equal(pages[1].file, "area.md");
    expect_equal(pages[1].title, "area.pep");
    expect_equal(pages[2].file, "solids-module.md");
    expect_equal(pages[2].title, "shapes.solids");

    var area = pages[1].markdown;
    expect_contains(area, "<!-- Generated from area.pep by `pep-doc package`. Do not edit. -->\n\n# area.pep\n");
    expect_contains(area, "\n## square\n\n```pepper\nsquare(side: int): int\n```\n\nReturns the area");
    expect_contains(
        area,
        "[BuildOption(\"shapes_fast\")] quick(): int\n```\n\nAvailable with the [feature](README.md#features) `fast`.\n"
    );
    expect_contains(area, "\nAvailable with the [feature](README.md#features) `tls`.\n\nA secure thing.");
    expect_contains(area, "construct()\n```\n\nAvailable with the [feature](README.md#features) `fast`.\n");
    # Neither `!` nor `||` makes a feature needed.
    expect_contains(area, "slow()\n```\n\nOnly without the feature.");

    var index = package_index(manifest, pages);
    expect_contains(index, "# shapes 1.2.0\n\nAreas and volumes\n");
    expect_contains(index, "- [shapes.solids](solids-module.md): Solids.\n");
    expect_contains(
        index, "- `default`: turns on `fast`\n- `fast`: turns on nothing else\n- `tls`: turns on `dep:semver`\n"
    );
    # The book is served from docs.pepper-lang.dev (#299).
    expect_contains(index, "(see [Features](https://docs.pepper-lang.dev/dev/tools/projects.html#features))");
    expect_contains(index, "- [`semver`](https://pep-lang.github.io/pepper-semver/) (optional)\n");
    expect_contains(index, "- `local`\n");

    # Re-exports link to this package's pages, and not to another module's.
    expect_contains(pages[0].markdown, "- Everything [`area.pep`](area.md) exports.\n");
    expect_contains(pages[0].markdown, "- Everything [the `shapes.solids` module](solids-module.md) exports.\n");
    expect_contains(pages[0].markdown, "- `JsonValue` from the `json` module.\n");
    expect_contains(index, "- [`win`](https://codeberg.org/someone/win) (only for `OS(Windows)`)\n");

    var book = folder.path.join(".pep").join("doc");
    write_file(book.join("src").join("gone.md"), "an earlier run's page");
    expect_true(write_book(book, manifest, pages).is_ok());
    expect_equal(
        read_file(book.join("src").join("SUMMARY.md")),
        "# Summary\n\n[shapes](README.md)\n\n- [shapes](module.md)\n- [area.pep](area.md)\n- [shapes.solids](solids-module.md)\n"
    );
    expect_equal(read_file(book.join("src").join("area.md")), area);
    expect_equal(read_file(book.join("src").join("README.md")), index);
    expect_false(book.join("src").join("gone.md").is_file());
    # A root `README.pep` would take the front page's file.
    expect_true(write_book(book, manifest, [Page("README.md", "README.pep", "")]).is_err());
    expect_equal(read_file(book.join("book.toml")), "[book]\ntitle = \"shapes\"\n");
}

[Test]
package_check_reports_undocumented_declarations() {
    var folder = TempFolder("pep_doc_package_check");
    write_package(folder.path);
    var checked = run(
        process
            .Command(tool("pep-doc").to_string())
            .arguments(["package", "--check"])
            .working_directory(folder.path.join("solids"))
    );
    expect_exit(checked, 1);
    expect_contains(checked.stderr, "area.pep:31:8: error: missing doc comment for 'undocumented'");
    expect_contains(checked.stderr, "error: 1 public declaration(s) without a doc comment");

    write_file(folder.path.join("area.pep"), "## Documented.\nexport fine() {}\n");
    expect_exit(
        run(
            process
                .Command(tool("pep-doc").to_string())
                .arguments(["package", "--check"])
                .working_directory(folder.path)
        ),
        0
    );
}

# What a package writes cannot become HTML on its pages (#301): raw HTML
# outside code shows as text, and a link to a script goes nowhere; code,
# safe links and the generated header stay as they are.
[Test]
package_markdown_is_inert() {
    var zero_width = "&#8203;";
    expect_equal(inert_markdown("a <script>x</script> & b"), "a &lt;script>x&lt;/script> &amp; b");
    expect_equal(inert_markdown("keep `a < b` and ``x`<`y``"), "keep `a < b` and ``x`<`y``");
    expect_equal(inert_markdown("```\n<b>\n```\n<i>"), "```\n<b>\n```\n&lt;i>");
    # Only what CommonMark takes for code passes as written.
    expect_equal(inert_markdown("text\n    ```\n<i>"), "text\n    ```\n&lt;i>");
    expect_equal(inert_markdown("``` a`b\n<i>"), "``` a`b\n&lt;i>");
    expect_equal(inert_markdown("- item\n\n    <i>"), "- item\n\n    &lt;i>");
    expect_equal(inert_markdown("\\`<i>`"), "\\`&lt;i>`");
    expect_equal(inert_markdown("`<i>`` x"), "`&lt;i>`` x");
    # No link can reach a script, wherever its target is.
    expect_equal(inert_markdown("[a](javascript:alert(1))"), $"[a](javascript{zero_width}:alert(1))");
    expect_equal(inert_markdown("[r]:\n  JavaScript:x"), $"[r]:\n  JavaScript{zero_width}:x");
    expect_equal(inert_markdown("[c](javascript&#58;x) data:x"), $"[c](javascript&amp;#58;x) data{zero_width}:x");
    expect_equal(inert_markdown("metadata: [e](https://x.dev/a)"), "metadata: [e](https://x.dev/a)");
    # mdBook's directives stay text, in code too.
    expect_equal(
        inert_markdown("{{#include /etc/passwd}}\n```\n{{#include x}}\n```"),
        "\\{{#include /etc/passwd}}\n```\n\\{{#include x}}\n```"
    );
}

# With `--docs-base`, a dependency's docs are on that site, under its
# source; a folder dependency still has none.
[Test]
docs_base_links_dependencies_by_source() {
    var folder = TempFolder("docs_base");
    write_package(folder.path);
    var manifest = load_manifest(folder.path.join("pep.toml"), Array<Path>()).value();
    var index = package_index(manifest, Array<Page>(), Optional<String>.Value("https://pkg.example/docs/"));
    expect_contains(index, "[`semver`](https://pkg.example/docs/github.com/Pep-Lang/pepper-semver/)");
    expect_contains(index, "[`win`](https://pkg.example/docs/codeberg.org/someone/win/)");
    expect_contains(index, "- `local`");
}

# Text that is not ASCII passes through whole; after a letter that is not
# ASCII, a scheme's name still counts as starting a word.
[Test]
inert_markdown_keeps_other_scripts() {
    expect_equal(inert_markdown("héllo <wörld> 日本 `ä<` éjavascript:"), "héllo &lt;wörld> 日本 `ä<` éjavascript&#8203;:");
}

# `pep-doc package` only parses a package: the files it is made of import
# no part of the compiler that checks, builds or runs code, nor `process`,
# so documenting a package the site does not trust runs none of its code
# (#301). Main runs only mdBook.
[Test]
package_docs_run_no_package_code() {
    var forbidden = [
        "compiler.sema", "compiler.driver", "compiler.codegen", "compiler.incremental", "compiler.desugar", "jit"
    ];
    for (var file in ["package.pep", "reference.pep", "inert.pep", "main.pep"]) {
        var text = read_file(Path("pep-doc").join(file));
        for (var line in text.lines()) {
            if (!line.starts_with("import ")) {
                continue;
            }
            for (var name in forbidden) {
                if (line.contains(name)) {
                    panic($"pep-doc/{file} imports {name}: `{line}`");
                }
            }
            if (file != "main.pep" and line.contains("process")) {
                panic($"pep-doc/{file} imports process: `{line}`");
            }
        }
    }
}
