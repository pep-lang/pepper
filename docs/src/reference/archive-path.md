<!-- Generated from runtime/archive/path.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Entry paths

`safe_components`: checking an entry's path before extracting it, so an
archive cannot write outside the directory it is extracted into.

Source: `runtime/archive/path.pep`

## safe_components

```pepper
safe_components(path: String): String[]?
```

Splits the path of an archive entry into its components, or gives none
when extracting it could write outside the target directory ("zip
slip"): an absolute path, a `..` component, a `\` or a `:` (which
Windows would read as a separator or a drive letter). Empty and `.`
components are left out, so `a//./b/` gives `a` and `b`.

`TarReader.extract` checks every entry with it, and so does the zip
package; a reader of another archive format should too.

**Parameters**
- `path` — the entry's path as stored, with `/` between components

**Returns**
- the components to join onto the target directory, or none for an unsafe path

**Example**
```pepper
import archive;

assert(archive.safe_components("docs/./readme.md").value().count == 2, "safe");
assert(archive.safe_components("../etc/passwd").is_empty(), "climbs out");
assert(archive.safe_components("C:/Windows").is_empty(), "a drive");
```
