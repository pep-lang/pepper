# pep-doc's parts: doc comments and the documentation standard, the
# reference's signatures and re-exports, the help parsing behind the
# tool-option check, the chapter lint, and the site's versions. `pep-doc
# check` itself runs in CI on the whole repository.

import [DocComment, check_documented, doc_comment_of, file_doc] from compiler.doc;
import [Directory, File, Path] from io;
import [TempFolder] from testing;
import "book";
import "checks";
import "reference";
import "site";

# The errors `check_documented` reports for the file `t.pep` holding
# `source`.
errors(source: String): String[] {
    var module = parse_file("t.pep", source);
    expect_true(module.is_ok());
    if (module.is_err()) {
        return Array<String>();
    }
    return check_documented(module.value(), source, "t.pep", Array<String>());
}

# The doc comment of the first declaration in `source`.
first_doc(source: String): DocComment? {
    var module = parse_file("t.pep", source).value();
    return doc_comment_of(source, module.declarations[0]);
}

[Test]
parses_the_description_and_the_tags() {
    var source = "## Adds two numbers.\n##\n## More text.\n## @param a the first\n##   continued\n## @returns the sum\n## @example\n##     add(1, 2);\nexport add(a: int, b: int): int { return a + b; }\n";
    var doc = first_doc(source).value();
    expect_equal(doc.description, "Adds two numbers.\n\nMore text.");
    expect_equal(doc.tags[0].name, "a");
    expect_equal(doc.tags[0].text, "the first continued");
    expect_equal(source.substr_bytes(doc.tags[0].span.start, doc.tags[0].span.end - doc.tags[0].span.start), "a");
    expect_equal(doc.tags[1].kind, "returns");
    expect_equal(doc.tags[2].text, "    add(1, 2);");
    expect_equal(
        doc.to_markdown(),
        "Adds two numbers.\n\nMore text.\n\n**Parameters**\n- `a` — the first continued\n\n**Returns**\n- the sum\n\n**Example**\n```pepper\nadd(1, 2);\n```"
    );
}

[Test]
looks_past_attributes_export_and_static() {
    var source = "## Doc [with brackets]\n[Target(OS(Linux))] export f(): void {}\nexport struct S {\n    ## Makes one.\n    ## @returns it\n    static make(): S { return S(); }\n}\n";
    expect_equal(first_doc(source).value().description, "Doc [with brackets]");
    var found = errors(source);
    expect_equal(found.count, 1 as ulong);
    expect_true(found[0].contains("missing doc comment for 'S'"));
}

[Test]
plain_comments_and_detached_blocks_are_not_doc_comments() {
    var found = errors(
        "# not docs\nexport f(): void {}\n## detached\n\nexport g(): void {}\n### rule\nexport h(): void {}\n"
    );
    expect_equal(found.count, 3 as ulong);
    expect_equal(
        found[0], "t.pep:2:8: error: missing doc comment for 'f'\n    2 | export f(): void {}\n      |        ^"
    );
}

[Test]
caller_location_parameters_are_not_documented() {
    expect_equal(
        errors(
            "## Checks.\n##\n## @param x the value\nexport f(x: int, location: __ptr<char> = __caller_location()): void {}\n"
        ).count,
        0 as ulong
    );
    var found = errors(
        "## Checks.\n##\n## @param x the value\n## @param location where\nexport f(x: int, location: __ptr<char> = __caller_location()): void {}\n"
    );
    expect_equal(found.count, 1 as ulong);
    expect_true(
        found[0].starts_with("t.pep:4:11: error: '@param location' documents a '__caller_location()' parameter")
    );
}

[Test]
a_file_doc_needs_a_blank_line_after_it() {
    expect_equal(file_doc("## The file.\n## More.\n\nimport \"x\";\n").value().description, "The file.\nMore.");
    expect_true(file_doc("## A function.\nexport f(): void {}\n").is_empty());
    expect_true(file_doc("# plain\n").is_empty());
}

[Test]
reports_missing_and_stale_tags() {
    var found = errors("##\n## Does it.\n## @param x an x\nexport f(y: int): int { return y; }\n");
    expect_equal(found.count, 3 as ulong);
    expect_true(found[0].starts_with("t.pep:4:10: error: missing '@param y' in the doc comment for 'f'"));
    expect_true(found[1].starts_with("t.pep:3:11: error: '@param x' names no parameter of 'f'"));
    expect_true(found[2].starts_with("t.pep:4:19: error: missing '@returns' in the doc comment for 'f'"));
}

[Test]
private_and_internal_declarations_need_no_docs() {
    var source = "f(): void {}\nexport _internal(): void {}\n## A box.\n## @typeParam T the item\nexport struct Box<T> {\n    ## The item.\n    var item: T;\n    var _cache: ulong;\n    _helper(): void {}\n}\n";
    expect_equal(errors(source).count, 0 as ulong);
}

[Test]
indexers_need_docs_and_overrides_name_no_generic_parameters() {
    var source = "## A box.\nexport struct Box {\n    [](index: ulong): int { return 0; }\n}\n## Hash.\n## @typeParam T any\n## @param v it\n## @returns h\nexport h<T>(v: T): int { return 0; }\n## Hash a String.\n## @param v it\n## @returns h\nexport h<String>(v: String): int { return 1; }\n";
    var found = errors(source);
    expect_equal(found.count, 1 as ulong);
    expect_true(found[0].contains("missing doc comment for 'Box.[]'"));
}

[Test]
an_override_for_a_struct_of_the_file_names_no_generic_parameters() {
    var source = "## A set.\nexport struct Bits {\n}\n## Hash a set.\n## @param v it\n## @returns h\nexport hash<Bits>(v: Bits): u64 { return 0; }\n";
    expect_equal(errors(source).count, 0 as ulong);
}

[Test]
requires_type_parameters() {
    var found = errors("## A box.\nexport struct Box<T> {\n}\n");
    expect_equal(found.count, 1 as ulong);
    expect_true(found[0].contains("missing '@typeParam T' in the doc comment for 'Box'"));
}

# The reference's signature of the first function in `source`.
signature_of(source: String): String {
    var module = parse_file("runtime/t.pep", source).value();
    var signature = "";
    if (module.declarations[0] is Function(f)) {
        signature = function_signature(source, f);
    }
    return signature;
}

[Test]
signatures_leave_out_caller_location_parameters() {
    expect_equal(
        signature_of("export f(x: int, location: __ptr<char> = __caller_location()): int { return x; }"),
        "f(x: int): int"
    );
    expect_equal(signature_of("export g(location: __ptr<char> = __caller_location(), y: int = 0) {}"), "g(y: int = 0)");
    expect_equal(signature_of("export h(location: __ptr<char> = __caller_location()) {}"), "h()");
}

[Test]
re_exports_link_to_their_sources() {
    var source = "export * from \"types\";\nexport [Path, join as combine] from \"path\";\nexport * from async;\n";
    var module = parse_file("runtime/io/module.pep", source).value();
    expect_equal(
        reexports(module, "io/module.pep", ""),
        "\n## Re-exports\n\n- Everything [`types.pep`](io-types.md) exports.\n- `Path` from [`path.pep`](io-path.md).\n- `join` (as `combine`) from [`path.pep`](io-path.md).\n- Everything [the `async` module](async-module.md) exports.\n"
    );
}

[Test]
built_ins_read_as_what_they_declare() {
    expect_equal(
        built_in_signature("[__BuiltIn(\"reflect.name\")] name<T>(): String", "name", "reflect.name"),
        "reflect.name<T>(): String"
    );
    expect_equal(member_title("[]"), "operator []");
    expect_equal(member_title("count"), "count");
}

# The module a runtime file belongs to (`io` for `io/path.pep`), or empty
# for a file at the top of the runtime.
module_of(file: String): String {
    var slash = file.find("/");
    return slash < 0 ? "" : file.substr_bytes(0, slash as ulong);
}

[Test]
pages_keep_each_module_together_under_its_module_file() {
    var seen = Array<String>();
    var current = "";
    for (var (file, _) in pages()) {
        var module = module_of(file);
        # The prelude's files come before every module's.
        expect_true(!module.is_empty or seen.is_empty);
        if (module == current) {
            continue;
        }
        current = module;
        # A module's files are not split up.
        expect_false(seen.contains(module));
        expect_equal(file, $"{module}/module.pep");
        seen.append(module);
    }
}

[Test]
the_first_sentence_ends_outside_code() {
    expect_equal(first_sentence("<!-- x -->\n\n# T\n\nSays `a. b` here. Then more.\n"), "Says `a. b` here.");
}

[Test]
help_parsing_finds_every_spelling() {
    var help = "usage: tool\n\nOptions:\n  -w, --write  rewrite\n      --check  list\n  --site <DIR>  a\n                continued -x\n  -O[=LEVEL]  b\n      --lto <MODE>  c [possible values: full, off]\nAfter:\n  --not-an-option\n";
    expect_equal(", ".join(help_options(help)), "-w, --write, --check, --site, -O, --lto");
    expect_equal(", ".join(help_values(help)), "--lto full, --lto off");
    expect_true(mentions("`-O` alone", "-O"));
    expect_false(mentions("`-O2` only", "-O"));
    expect_false(mentions("--lto only", "-l"));
    expect_true(mentions("ends with -T time.", "-T time"));
    expect_true(mentions_variable("`PEPPER_SYSROOT_<TRIPLE>`", "PEPPER_SYSROOT_AARCH64_APPLE_DARWIN"));
    expect_equal(", ".join(variables_named("set PEPPER_A or PEPPER_B_C, not XPEPPER_D")), "PEPPER_A, PEPPER_B_C");
    expect_equal(", ".join(help_commands("Commands:\n  add   adds\n  list  lists\n\nOptions:\n")), "add, list");
}

[Test]
an_include_inside_a_list_item_is_an_error() {
    var found = lint_chapter("src/a.md", "- item:\n\n  ```pepper\n  {{#include ../examples/a.pep}}\n  ```\n");
    expect_equal(found.count, 1 as ulong);
    expect_equal(
        found[0],
        "src/a.md:4:3: error: an indented include breaks the code block it sits in; move the example out of the list to column 0"
    );
    expect_equal(lint_chapter("src/a.md", "```pepper\n{{#include ../examples/a.pep}}\n```\n").count, 0 as ulong);
}

[Test]
parses_and_orders_versions() {
    expect_equal(parse_version("v1.2.3").value().to_string(), "1.2.3");
    expect_equal(parse_version("0.1.0-beta.1").value().prerelease, "beta.1");
    for (var bad in ["1.2", "1.2.x", "01.2.3", "1.2.3-", "dev"]) {
        expect_true(parse_version(bad).is_err());
    }
    var versions = Array<Version>();
    for (var text in ["0.10.0", "0.2.0", "1.0.0-rc.1", "1.0.0"]) {
        versions.append(parse_version(text).value());
    }
    versions.sort((a, b) => a.compare(b));
    var names = Array<String>();
    for (var v in versions) {
        names.append(v.to_string());
    }
    expect_equal(", ".join(names), "0.2.0, 0.10.0, 1.0.0-rc.1, 1.0.0");
}

[Test]
the_index_keeps_every_version_and_opens_the_newest_release() {
    var folder = TempFolder("pep_doc_site");
    for (var v in ["0.1.0", "0.2.0", "0.3.0-beta.1", "dev", "not-a-version"]) {
        Directory.create_all(folder.path.join(v));
        File.write_text(folder.path.join(v).join("index.html"), "");
    }
    expect_true(write_index(folder.path, "Pepper documentation").is_ok());
    expect_equal(
        File.read_to_string(folder.path.join("versions.json")).value(),
        "{\n  \"latest\": \"0.2.0\",\n  \"versions\": [\n    \"0.3.0-beta.1\",\n    \"0.2.0\",\n    \"0.1.0\",\n    \"dev\"\n  ]\n}\n"
    );
    expect_true(File.read_to_string(folder.path.join("index.html")).value().contains("url=0.2.0/"));
    expect_true(File.read_to_string(folder.path.join("latest").join("index.html")).value().contains("url=../0.2.0/"));
    expect_true(File.read_to_string(folder.path.join("404.html")).value().contains("\"/0.2.0/\""));
    expect_true(folder.path.join(".nojekyll").is_file());
    # `latest/` is not a version.
    expect_equal(", ".join(versions_in(folder.path)), "0.3.0-beta.1, 0.2.0, 0.1.0, dev");
}

[Test]
tool_versions_are_held_to_the_version_file() {
    expect_equal(tool_version("import x;\n\nversion(): String {\n    return \"1.2.3-dev\";\n}\n").value(), "1.2.3-dev");
    expect_equal(
        tool_version("import x;\n\nexport version(): String {\n    return \"1.2.3-dev\";\n}\n").value(), "1.2.3-dev"
    );
    expect_true(tool_version("main(): int { return 0; }\n").is_empty());

    var folder = TempFolder("pep_doc_versions");
    File.write_text(folder.path.join("VERSION"), "1.2.3\n");
    for (var tool in ["a", "b", "c", "d"]) {
        Directory.create_all(folder.path.join("tools").join(tool));
    }
    File.write_text(
        folder.path.join("tools").join("a").join("main.pep"), "\nversion(): String {\n    return \"1.2.3\";\n}\n"
    );
    File.write_text(
        folder.path.join("tools").join("b").join("main.pep"), "\nversion(): String {\n    return \"1.2.2\";\n}\n"
    );
    # A version() in arguments.pep (pep-lsp's) is checked too.
    File.write_text(
        folder.path.join("tools").join("d").join("arguments.pep"),
        "\nexport version(): String {\n    return \"1.2.1\";\n}\n"
    );
    # A tool without a version() is not checked.
    File.write_text(folder.path.join("tools").join("c").join("main.pep"), "main(): int { return 0; }\n");
    var stale = stale_versions(folder.path).value();
    expect_equal(stale.count, 2 as ulong);
    expect_equal(
        stale[0], "tools/b/main.pep: version() returns '1.2.2', but VERSION holds '1.2.3'; run scripts/set-version.sh"
    );
    expect_equal(
        stale[1],
        "tools/d/arguments.pep: version() returns '1.2.1', but VERSION holds '1.2.3'; run scripts/set-version.sh"
    );
}

[Test]
a_bare_export_in_the_module_makes_a_declaration_public() {
    var folder = TempFolder("pep_doc_reexport");
    var shapes = folder.path.join("shapes");
    Directory.create_all(shapes);
    File.write_text(
        shapes.join("area.pep"),
        "## Returns one.\n##\n## @returns 1\narea(): int { return 1; }\nvolume(): int { return 2; }\nhidden(): int { return 3; }\n"
    );
    File.write_text(
        shapes.join("module.pep"), "import \"area\";\nimport \"sys\";\n\nexport area;\nexport volume;\nexport Box;\n"
    );
    # Neither an extern of an exported name nor an extension of an
    # exported type is what the export names.
    File.write_text(shapes.join("sys.pep"), "extern int volume();\nstruct Box {}\nextend Box with Copy;\n");
    # A file of another folder is not part of the module.
    File.write_text(folder.path.join("other.pep"), "volume(): int { return 4; }\n");
    var files = read_library(
        folder.path, ["shapes/area.pep", "shapes/module.pep", "shapes/sys.pep", "other.pep"], ""
    ).value();
    var area = files[0];
    var body = page_body(area.module, area.source, Array<(String, String)>(), area.reexported);
    expect_true(body.contains("area(): int"));
    expect_true(body.contains("volume(): int"));
    expect_false(body.contains("hidden"));
    var found = check_documented(area.module, area.source, area.name, area.reexported);
    expect_equal(found.count, 1 as ulong);
    expect_true(found[0].starts_with("shapes/area.pep:5:1: error: missing doc comment for 'volume'"));
    var sys = files[2];
    var sys_body = page_body(sys.module, sys.source, Array<(String, String)>(), sys.reexported);
    expect_true(sys_body.contains("## Box"));
    expect_false(sys_body.contains("extend"));
    expect_false(sys_body.contains("volume"));
    expect_true(files[3].reexported.is_empty);
}
