## `safe_components`: checking an entry's path before extracting it, so an
## archive cannot write outside the directory it is extracted into.

## Splits the path of an archive entry into its components, or gives none
## when extracting it could write outside the target directory ("zip
## slip"): an absolute path, a `..` component, a `\` or a `:` (which
## Windows would read as a separator or a drive letter). Empty and `.`
## components are left out, so `a//./b/` gives `a` and `b`.
##
## `TarReader.extract` checks every entry with it, and so does the zip
## package; a reader of another archive format should too.
##
## @param path the entry's path as stored, with `/` between components
## @returns the components to join onto the target directory, or none for
##   an unsafe path
## @example
##     import archive;
##
##     assert(archive.safe_components("docs/./readme.md").value().count == 2, "safe");
##     assert(archive.safe_components("../etc/passwd").is_empty(), "climbs out");
##     assert(archive.safe_components("C:/Windows").is_empty(), "a drive");
export safe_components(path: String): String[]? {
    if (path.starts_with("/") || path.contains("\\") || path.contains(":")) {
        return Optional<String[]>.Empty;
    }
    var components = Array<String>();
    for (var component in path.split("/")) {
        if (component == "..") {
            return Optional<String[]>.Empty;
        }
        if (!component.is_empty && component != ".") {
            components.append(component);
        }
    }
    return Optional<String[]>.Value(components);
}
