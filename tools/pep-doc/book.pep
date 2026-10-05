# Checks on the book's own chapters that mdBook does not make: Markdown
# that renders without an error but comes out broken.

import [Directory, File, Path] from io;
import "strings";

# A chapter: its path from the repository root and its text.
struct _Chapter {
    var name: String;
    var text: String;

    construct(name: String, text: String) {
        this.name = name;
        this.text = text;
    }
}

# Every `.md` file under `dir`, named `prefix` followed by its path from
# `dir`.
_chapters(dir: Path, prefix: String, out: Array<_Chapter>): Result<void> {
    var listing = Directory.open(dir);
    if (listing.is_err()) {
        return Result<void>.Err($"cannot read {dir.to_string()}: {listing.error().message}");
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return Result<void>.Err($"cannot read {dir.to_string()}: {entries.error().message}");
    }
    for (var entry in entries.value()) {
        if (entry.is_directory) {
            _chapters(entry.path, $"{prefix}{entry.name}/", out)?;
            continue;
        }
        if (!entry.name.ends_with(".md")) {
            continue;
        }
        var text = File.read_to_string(entry.path);
        if (text.is_err()) {
            return Result<void>.Err($"cannot read {entry.path.to_string()}: {text.error().message}");
        }
        out.append(_Chapter(prefix + entry.name, normalized(text.value())));
    }
    return Result<void>.ok();
}

# The problems in one chapter, each as `file:line:col: error: message`.
#
# An indented `{{#include}}` (one inside a list item) pastes the file's
# lines at column 0, which ends the list item and the code block around
# it: the rest of the example renders as prose, and its `#` comments as
# headings.
export lint_chapter(file: String, text: String): String[] {
    var errors = Array<String>();
    ulong number = 0;
    for (var line in text.lines()) {
        number += 1;
        var trimmed = line.trim_start();
        var indent = line.size - trimmed.size;
        if (indent == 0) {
            continue;
        }
        if (trimmed.starts_with("{{#include") or trimmed.starts_with("{{#rustdoc_include")) {
            errors.append(
                $"{file}:{number}:{indent + 1}: error: an indented include breaks the code block it sits in; move the example out of the list to column 0"
            );
        }
    }
    return errors;
}

# The problems in every chapter under `src_dir`, the book's `docs/src`
# folder, naming each file by its path from the repository root.
export lint(src_dir: Path): Result<String[]> {
    var chapters = Array<_Chapter>();
    _chapters(src_dir, "docs/src/", chapters)?;
    chapters.sort((a, b) => a.name.compare(b.name));
    var errors = Array<String>();
    for (var chapter in chapters) {
        errors.append_all(lint_chapter(chapter.name, chapter.text));
    }
    return Result<String[]>.ok(errors);
}
