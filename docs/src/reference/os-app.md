<!-- Generated from runtime/os/app.pep by `pep-doc reference`. Do not edit. -->

# App folders

The folders an iOS or Android app keeps its files in.

Source: `runtime/os/app.pep`

## AppDirectories

```pepper
struct AppDirectories
```

The folders of an iOS or Android app: where it keeps the files the user
makes, what it can make again, and scratch files. Each is inside the
app's own container, which only the app can write.

**Example**
```pepper
import io;
import os;

var folders = os.app_directories();
if (folders) {
    io.File.write_text(folders.value().documents.join("notes.txt"), "kept");
}
```

### Fields

#### documents

```pepper
const documents: io.Path
```

The folder for the user's files, kept and backed up: iOS's
`Documents`, Android's `Context.getFilesDir()`.

#### cache

```pepper
const cache: io.Path
```

The folder for files the app can make again, which the system may
remove when it runs short of space: iOS's `Library/Caches`, Android's
`Context.getCacheDir()`.

#### temp

```pepper
const temp: io.Path
```

The folder for scratch files: iOS's `tmp` (`NSTemporaryDirectory()`),
and on Android the cache folder. `io.Directory.temp()` is the same
folder.

### Constructor

#### AppDirectories()

```pepper
construct(documents: io.Path, cache: io.Path, temp: io.Path)
```

Creates the folders.

**Parameters**
- `documents` — the folder for the user's files
- `cache` — the folder for files the app can make again
- `temp` — the folder for scratch files

## app_directories

```pepper
app_directories(): AppDirectories?
```

Returns the app's folders on iOS and Android.

On iOS they come from Foundation (`NSSearchPathForDirectoriesInDomains`
and `NSTemporaryDirectory`), for an app and for a program the simulator
runs. Android gives native code no way to find them, so the app passes
them in first, through `pepper_set_app_directories` (see
[iOS and Android](../language/mobile.md)); until it does there are none.
Other systems have no app folders.

**Returns**
- the folders, or none on another system, on Android before the app passes them, and when Foundation cannot be opened

**Example**
```pepper
import os;

var folders = os.app_directories();
if (folders) {
    print(folders.value().cache.to_string());
}
```
