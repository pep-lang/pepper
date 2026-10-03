# Standard library reference

The standard library is the Pepper runtime: the files under `runtime/` that
every program is compiled with. The pages listed first (from Built-in
functions to URI) are the prelude, available without an import. Each module
after them (`io`, `async`, `json`, ...) is brought in with an import, such
as `import io` or `import [File, Path] from io`; its other pages are listed
under it.

These pages are generated from the doc comments in the runtime's source (see
[Documentation comments](../language/doc-comments.md)), so they always match
the version of Pepper they were built with. Use the version picker at the top
of the page to read the reference for another release.
