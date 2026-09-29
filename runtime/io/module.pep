# The io module: files, directories and paths (modeled on Rust's std::fs and
# std::path). `import io` or `import [File, Path] from io`.
#
# This file only gathers the module's public API from its other files. The
# platform layer (`_io_sys_*` in sys_posix.pep / sys_windows.pep) and the
# `_io_*` helpers are exported between the io files but not from the module.

import "types";
import "path";
import "file";
import "directory";

export FileHandle;
export ErrorCode;
export Mode;
export Offset;
export IoError;
export IoResult;

export Path;

export OpenOptions;
export Metadata;
export File;

export DirEntry;
export Directory;
