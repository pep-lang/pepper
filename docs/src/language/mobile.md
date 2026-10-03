# iOS and Android

Pepper compiles natively for iOS and Android through the same LLVM backend
it uses everywhere else: `--target` picks the platform, and the result is
ordinary machine code for an iPhone, an iPad, the iOS simulator, or an
Android phone. An app calls the Pepper code through C, as any C library is
called: mark the functions `[Export]`, build a library with `--lib static`
(see [Calling Pepper from C](c-interop.md#calling-pepper-from-c)), and call
it from Swift directly, or from Kotlin and Java through JNI.

## Targets

| Triple                        | Runs on                                   |
|-------------------------------|-------------------------------------------|
| `aarch64-apple-ios`           | iPhone and iPad                           |
| `aarch64-apple-ios-simulator` | the iOS simulator on an Apple silicon Mac |
| `x86_64-apple-ios-simulator`  | the iOS simulator on an Intel Mac         |
| `aarch64-linux-android`       | Android phones and tablets (`arm64-v8a`)  |
| `x86_64-linux-android`        | the Android emulator on x64 (`x86_64`)    |

- **Versions.** A triple can name the oldest OS version the code runs on:
  `aarch64-apple-ios17.0`, `aarch64-apple-ios17.0-simulator`,
  `aarch64-linux-android33`. Without one, iOS code runs on iOS 15 and later
  and Android code on API level 30 (Android 11) and later. Pepper's runtime
  needs API level 30, so an older one is an error:

  ```text
  error: unsupported target 'aarch64-linux-android24': Pepper's runtime needs Android API level 30 or later (write 'android30')
  ```

- **Spellings.** `arm64` works for `aarch64`, as do Rust's `-sim` for
  `-simulator` and any vendor (`aarch64-unknown-linux-android`).
  `x86_64-apple-ios` means the simulator, since no iPhone is x64.
- **CPU.** Code for an iPhone runs on every arm64 iPhone (clang's
  `apple-a7`); add `-mcpu=apple-a14` to use what newer ones have. Android
  x64 code uses SSE4.2 and POPCNT, which the Android x86_64 ABI requires.

## Building

A library for an app needs no SDK, only the compiler:

```sh
pepper build --target aarch64-apple-ios --lib static greeter.pep -o ios/libgreeter.a
pepper build --target aarch64-linux-android --lib static greeter.pep -o android/libgreeter.a
```

Each writes `greeter.h` beside the library. Build the library once for each
target the app ships: the device and the simulator on iOS, and each
Android ABI.

Linking, for a shared library or an executable to run in the simulator or
an emulator, needs the platform's SDK:

- **iOS** links with LLVM's `ld64.lld` against an iOS SDK. On a Mac with
  Xcode the compiler asks `xcrun` for it (`iphoneos`, or `iphonesimulator`
  for the simulator). Elsewhere name it with `--sysroot`, or set
  `PEPPER_SYSROOT_AARCH64_APPLE_IOS` (and
  `PEPPER_SYSROOT_AARCH64_APPLE_IOS_SIMULATOR`, and so on): the variable is
  named for the triple without its version.
- **Android** links with the NDK's own clang, which brings the NDK's
  linker, compiler-rt and unwinder. Name the NDK with `--sysroot <ndk>` or
  `PEPPER_SYSROOT_AARCH64_LINUX_ANDROID`, or set `ANDROID_NDK_HOME` or
  `ANDROID_NDK_ROOT`; otherwise the newest NDK in the Android SDK
  (`$ANDROID_HOME/ndk/<version>`, as Android Studio installs it) is used.
  NDK r27 is the version tested.

When the SDK is missing, the link error says where to point the compiler:

```text
note: linking for 'aarch64-linux-android30' needs the Android NDK (https://developer.android.com/ndk/downloads): pass '--sysroot <ndk>' or set PEPPER_SYSROOT_AARCH64_LINUX_ANDROID, ANDROID_NDK_HOME or ANDROID_HOME
```

## Selecting code for a platform

`[Target(OS(IOS))]` and `[Target(OS(Android))]` select code for one of
them. Most code needs neither: iOS is Darwin, like macOS, and Android runs
the Linux kernel, so `OS(Mac)` is true on iOS and `OS(Linux)` on Android,
as `TARGET_OS_MAC` and `__linux__` are in C (see
[Platform selection](platform-selection.md#writing-a-condition)). The
runtime's macOS and Linux code serves them, with a few declarations
narrowed where they differ. At run time, `os.system_os()` returns
`OperatingSystem.IOS` or `OperatingSystem.Android`.

## Calling Pepper from Swift

Swift calls C directly. Give `swiftc` the generated header as the bridging
header, and link the library:

```sh
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios15.0-simulator -parse-as-library \
  -import-objc-header greeter.h App.swift -L . -lgreeter -o App.app/App
```

In an Xcode project, add the library to the target's *Link Binary With
Libraries* phase and `#include "greeter.h"` in the target's bridging header.
A `String` crosses as a pointer and a size, and a returned string is freed
with `pepper_string_free`:

```swift
func pepperGreeting(_ name: String) -> String {
    let result = name.withCString { greet($0, strlen($0)) }!
    defer { pepper_string_free(result) }
    return String(cString: result)
}
```

## Calling Pepper from Kotlin or Java

Kotlin and Java reach C through JNI: a shared library holds the Pepper code
and a C function for each `native` method, named for its class, which
converts Java's types to the C ones the header declares. Link both with the
NDK's clang into the `.so` the app loads:

```sh
pepper build --target aarch64-linux-android --lib static greeter.pep -o pepper/libgreeter.a
$NDK/toolchains/llvm/prebuilt/*/bin/clang --target=aarch64-linux-android30 -shared -fPIC \
  -I pepper jni.c pepper/libgreeter.a -lm -o jniLibs/arm64-v8a/libgreeter.so
```

```c
JNIEXPORT jstring JNICALL
Java_dev_pepper_demo_MainActivity_greet(JNIEnv* env, jclass cls, jstring name) {
    const char* bytes = (*env)->GetStringUTFChars(env, name, NULL);
    char* result = greet(bytes, strlen(bytes));
    (*env)->ReleaseStringUTFChars(env, name, bytes);
    jstring greeting = (*env)->NewStringUTF(env, result);
    pepper_string_free(result);
    return greeting;
}
```

The Kotlin side declares the function `external` and loads the library
once:

```kotlin
class MainActivity : Activity() {
    companion object {
        init { System.loadLibrary("greeter") }
        @JvmStatic external fun greet(name: String): String
    }
}
```

With Gradle, put each ABI's `.so` in `src/main/jniLibs/<abi>/`
(`arm64-v8a`, `x86_64`), or build it from the module's `CMakeLists.txt`
with the static library as an imported target.

## Threads

Exported functions may be called from any thread (see
[Initialization, panics and threads](c-interop.md#initialization-panics-and-threads)),
so the app decides where Pepper code runs. Keep long work off the main
thread (iOS's main queue, Android's UI thread): call it from a background
queue, a coroutine on `Dispatchers.Default`, or a Pepper thread or task the
library starts itself. Pepper code never calls back into UIKit or Android's
views on its own; hand results back to the main thread on the app's side.

## What works differently

The runtime runs the documentation's examples on both platforms, with these
differences:

- **Starting processes.** An iOS app cannot start other programs, and the
  `process` module's `Command.spawn` returns an `IoError` there. On Android
  it works, but an app has few programs to start, and below API level 34
  `Command.working_directory` makes `spawn` return an `IoError` (bionic
  lacks `posix_spawn_file_actions_addchdir_np` there).
- **TLS.** The `tls` module (and HTTPS) loads OpenSSL at run time, which
  neither platform ships, so making a TLS context returns an `IoError`
  unless the app bundles `libssl`. Use the platform's own networking
  (`URLSession`, OkHttp) for HTTPS for now.
- **Files.** An app reads and writes inside its own container: pass the
  path the platform gives (`FileManager`'s documents directory,
  `Context.getFilesDir()`) to the Pepper code. `os.home_directory()` and
  the temporary directory point into the container on iOS. Android has no
  `/tmp`: without `TMPDIR`, `io.Directory.temp()` is `/data/local/tmp`,
  which an app cannot write, so an app passes its cache directory. A Unix
  socket's path is at most 104 bytes there, and the container's own path
  takes most of them, so give a socket there a short name. On Android, an
  app creates Unix socket files in its own data folder
  (`Context.getFilesDir()`); SELinux refuses them elsewhere, and from an
  `adb shell` program everywhere, with a permission error.
- **Backtraces.** Android's backtraces come from the NDK's unwinder
  (bionic's `backtrace` needs API level 33), and both platforms name
  functions from the binary's own symbols, so strip a release build only
  after keeping a copy for symbolication.
- **Standard output** goes to the Xcode console and the simulator's
  `--stdout` file on iOS. On Android it goes nowhere in an app: log with the
  platform's logger instead (`__android_log_write` through an `extern`).

## Shipping

- Pepper compiles ahead of time, so iOS's ban on JIT compilation does not
  apply. Bitcode is no longer required by the App Store.
- A static library is linked into the app's own binary, so its code is
  covered by the app's signature; strip the release build's symbols as
  usual (Xcode's *Strip Linked Product*, the Android Gradle plugin's
  `strip` of `jniLibs`). A Pepper library adds the runtime parts the
  program uses: the prototype app's library below is about 1 MB unstripped.
- Each Android ABI needs its own `.so`; Google Play requires `arm64-v8a`.

## Debugging

`-g` writes DWARF, which LLDB reads in both Xcode and Android Studio. Build
the library with `-g` and the app in its debug configuration, and set
breakpoints in the `.pep` files by path.

## The prototype apps

`docs/examples/mobile/` holds a small app for each platform that calls the
same Pepper library, [`greeter.pep`](../../examples/mobile/greeter.pep):

- `ios/`: a SwiftUI app (`PepperDemo.swift`), and `build.sh`, which builds
  it with `swiftc` for the simulator and for devices, installs it in a
  booted simulator, launches it and checks its output.
- `android/`: an activity in Java with the JNI functions in `jni.c`, and
  `build.sh`, which builds the APK with the Android SDK's own tools
  (`javac`, `d8`, `aapt2`, `apksigner`; Gradle is not needed), installs it
  in the emulator, starts it and checks its log.

`scripts/mobile-test.sh` runs both on a Mac with Xcode and the Android SDK:
it builds every documentation example for the iOS simulator and for Android,
runs each in the simulator (`xcrun simctl spawn`) and in the emulator
(`adb shell`), then builds and runs the two apps.

```sh
bash scripts/mobile-test.sh target/debug/pep-build /tmp/mobile all
```

## Not supported yet

- **TLS through the platform**: Security.framework on iOS, and on Android
  the system's BoringSSL through Conscrypt or a bundled OpenSSL.
- **Generated bindings**: the JNI layer and the Swift wrappers are written
  by hand; a generator could write them from the header.
- **Packaging**: an `.xcframework` holding the device and simulator
  libraries, a Swift package, and an Android library (`.aar`).
- **Other targets**: 32-bit Android (`armeabi-v7a`, `x86`), Mac Catalyst,
  tvOS, watchOS and visionOS.
