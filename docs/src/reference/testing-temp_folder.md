<!-- Generated from runtime/testing/temp_folder.pep by `pep-doc reference`. Do not edit. -->

# TempFolder

`TempFolder`, a test fixture: a fresh folder that is removed with
everything in it when the fixture is released.

Source: `runtime/testing/temp_folder.pep`

## TempFolder

```pepper
struct TempFolder
```

A fresh, empty folder under the system's temporary folder, for a test
that writes files. The folder and everything in it are removed when the
last reference to the fixture is released, so a test that holds it in a
local cleans up when it returns.

Its name joins the name the test gives with the process id, so tests
running at once, each in a process of its own, never share a folder.
When a folder of that name is left from an earlier run (whose process
had the same id) and cannot be removed, a number is added to the name,
so the folder is always new and empty.

**Example**
```pepper
[Test]
writes_a_file() {
    var folder = TempFolder("writes_a_file");
    var path = folder.path.join("notes.txt");
    io.File.write_text(path, "hello");
    expect_equal(io.File.read_to_string(path).value(), "hello");
}
```

### Fields

#### path

```pepper
const path: io.Path
```

The folder's path.

### Constructor

#### TempFolder()

```pepper
construct(name: String)
```

Makes the folder, removing what a crashed run left at its path, or
taking a numbered name when that cannot be removed.

**Parameters**
- `name` — a name for the folder, such as the test's

**Panics**
- if the folder cannot be made
