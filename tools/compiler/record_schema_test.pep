# A Pepper library's interface is a checked-unit record that another
# compiler reads (#220), which `link.RECORD_VERSION` names. So the code that
# writes and reads records is fingerprinted, its tokens without comments or
# spacing, and the fingerprint is kept here beside the version it was taken
# at: a change to that code fails until the version is bumped (when the
# record's encoding or meaning changed) and the fingerprint updated.

import digest;
import [File, Path] from io;
import compiler.link;
import syntax;

## The `link.RECORD_VERSION` the fingerprint below was taken at.
const _VERSION: uint = 1;

## The fingerprint of the record's code at `_VERSION`.
const _FINGERPRINT = "753a424e4e4a977faea40a613ec6379e";

[Test]
the_record_format_matches_its_version() {
    # The code that writes and reads a record, as paths from `tools/` and
    # the text each part of the file starts and ends at (the whole file
    # when empty).
    var code = [
        ("compiler/sema/record.pep", "", ""),
        ("compiler/sema/record_codec.pep", "", ""),
        ("compiler/sema/pending.pep", "", ""),
        ("compiler/sema/checked.pep", "export struct CheckedUnit {", "## Marks everything `module` declares"),
        ("compiler/incremental/compilation_units.pep", "_record_bytes(program: link.Program", ""),
        ("compiler/incremental/library_interface.pep", "", "")
    ];
    var hasher = digest.Blake3();
    for (var (path, start, end) in code) {
        var text = File.read_to_string(Path(path));
        expect_true(text.is_ok());
        var source = text.value();
        var from = start.is_empty ? 0 : source.find(start);
        expect_true(from >= 0);
        var rest = source.substr_bytes(from as ulong, source.size - from as ulong);
        var to = end.is_empty ? (rest.size as long) : rest.find(end);
        expect_true(to >= 0);
        var part = rest.substr_bytes(0, to as ulong);
        var tokens = syntax.lex(part);
        expect_true(tokens.is_ok());
        hasher.update($"{path}\n");
        for (var token in tokens.value()) {
            hasher.update(token.text(part));
            hasher.update("\n");
        }
    }
    var fingerprint = hasher.finish_hex().substr_bytes(0, 32);
    if (_VERSION != link.RECORD_VERSION or fingerprint != _FINGERPRINT) {
        print(
            $"the record format changed: bump RECORD_VERSION and update the fingerprint (record_schema_test.pep: _VERSION = {link.RECORD_VERSION}, _FINGERPRINT = \"{fingerprint}\")"
        );
    }
    expect_equal(_VERSION, link.RECORD_VERSION);
    expect_equal(fingerprint, _FINGERPRINT);
}
