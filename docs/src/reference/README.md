# Standard library reference

The standard library is the Pepper runtime: the files under `runtime/` that
every program is compiled with. Everything here is available without an
import, except the `io` module, which a program brings in with `import io`
(or `import [File, Path] from io`).

These pages are generated from the doc comments in the runtime's source (see
[Documentation comments](../language/doc-comments.md)), so they always match
the version of Pepper they were built with. Use the version picker at the top
of the page to read the reference for another release.
