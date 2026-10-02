//! `--lib static|shared`: a library C code links, instead of an executable
//! (see the book's "Calling Pepper from C").
//!
//! A static library is an archive of the program's objects, written here
//! with `ar_archive_writer` (the archive writer rustc uses) in the host's
//! format, so no archiver needs to be installed. A shared library is linked
//! by clang like an executable, with `-shared`. Beside either goes a C
//! header declaring the `[Export]`ed functions
//! (`pepper_sema::passes::exports::header`).

use std::path::{Path, PathBuf};

/// The kind of library `--lib` builds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LibraryKind {
    Static,
    Shared,
}

impl LibraryKind {
    /// `static` or `shared`, as `--lib` spells them.
    pub fn parse(text: &str) -> Option<LibraryKind> {
        match text {
            "static" => Some(LibraryKind::Static),
            "shared" => Some(LibraryKind::Shared),
            _ => None,
        }
    }

    /// The library's file name for `name` on the target: `libname.a`,
    /// `libname.so` or `libname.dylib`; `name.lib` or `name.dll` on Windows.
    pub fn file_name(self, name: &str) -> String {
        let os = &pepper_sema::current_target().os;
        match (self, os == "windows", os == "macos") {
            (LibraryKind::Static, true, _) => format!("{}.lib", name),
            (LibraryKind::Shared, true, _) => format!("{}.dll", name),
            (LibraryKind::Static, false, _) => format!("lib{}.a", name),
            (LibraryKind::Shared, false, true) => format!("lib{}.dylib", name),
            (LibraryKind::Shared, false, false) => format!("lib{}.so", name),
        }
    }
}

/// Where the C header for the library at `library` goes: beside it, named
/// for the library without its `lib` prefix (`libfoo.a` has `foo.h`).
pub fn header_path(library: &Path) -> PathBuf {
    let stem = library.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    let name = match stem.strip_prefix("lib") {
        Some(rest) if !rest.is_empty() && pepper_sema::current_target().os != "windows" => rest.to_string(),
        _ => stem,
    };
    library.with_file_name(format!("{}.h", name))
}

/// Write the static library `output`: an archive of `objects`, with a
/// symbol index, in the target's format.
pub fn write_archive(objects: &[PathBuf], output: &Path) -> Result<(), String> {
    use ar_archive_writer::{ArchiveKind, NewArchiveMember, DEFAULT_OBJECT_READER};
    let mut members = vec![];
    for object in objects {
        let bytes = std::fs::read(object).map_err(|e| format!("cannot read {}: {}", object.display(), e))?;
        // Members are named by unit, so two units' objects never share a
        // name inside the archive.
        let name = object.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        members.push(NewArchiveMember::new(bytes, &DEFAULT_OBJECT_READER, name));
    }
    let os = &pepper_sema::current_target().os;
    let kind = if os == "windows" {
        ArchiveKind::Coff
    } else if os == "macos" {
        ArchiveKind::Darwin
    } else {
        ArchiveKind::Gnu
    };
    let mut buffer = std::io::Cursor::new(Vec::new());
    ar_archive_writer::write_archive_to_stream(&mut buffer, &members, kind, false, None)
        .map_err(|e| format!("cannot write {}: {}", output.display(), e))?;
    std::fs::write(output, buffer.into_inner()).map_err(|e| format!("cannot write {}: {}", output.display(), e))
}

/// The bytes of `text` as lowercase hex, for a cache record.
pub(crate) fn to_hex(text: &str) -> String {
    text.bytes().map(|b| format!("{:02x}", b)).collect()
}

/// [`to_hex`] undone; `None` for text that is not such hex.
pub(crate) fn from_hex(hex: &str) -> Option<String> {
    if hex.len() % 2 != 0 {
        return None;
    }
    let bytes: Option<Vec<u8>> = (0..hex.len()).step_by(2).map(|i| u8::from_str_radix(hex.get(i..i + 2)?, 16).ok()).collect();
    String::from_utf8(bytes?).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_names() {
        if !cfg!(windows) {
            assert_eq!(header_path(Path::new("out/libfoo.a")), Path::new("out/foo.h"));
            assert_eq!(header_path(Path::new("libfoo.so")), Path::new("foo.h"));
        }
        assert_eq!(header_path(Path::new("bar.dll")), Path::new("bar.h"));
    }

    #[test]
    fn hex_round_trip() {
        let text = "int32_t add(int32_t a, int32_t b);\n\"quoted\"";
        assert_eq!(from_hex(&to_hex(text)).as_deref(), Some(text));
        assert_eq!(from_hex("zz"), None);
    }
}
