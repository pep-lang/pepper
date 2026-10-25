# iOS and Android

Pepper compiles natively for iOS and Android through the same LLVM backend
it uses everywhere else: `--target` picks the platform, and the result is
ordinary machine code for an iPhone, an iPad, the iOS simulator, or an
Android phone. An app calls the Pepper code through C, as any C library is
called: mark the functions `[Export]`, build a library with `--lib static`
(see [Calling Pepper from C](c-interop.md#calling-pepper-from-c)), or on iOS
an `.xcframework` or a Swift package (`--lib xcframework`, `--lib
swift-package`) and on Android an `.aar` (`--lib aar`), and call it from
Swift directly, or from Kotlin and Java through JNI.

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

The compiler writes each archive itself, in the format the platform's
linkers read (BSD's for iOS, GNU's for Android), so nothing from Xcode or
the NDK is needed to make it. Each writes `greeter.h` beside the library.
Build the library once for each
target the app ships: the device and the simulator on iOS, and each
Android ABI.

Linking, for a shared library or an executable to run in the simulator or
an emulator, needs the platform's SDK:

- **iOS** links with LLVM's `ld64.lld` against an iOS SDK. On a Mac with
  Xcode the compiler asks `xcrun` for it (`iphoneos`, or `iphonesimulator`
  for the simulator). Elsewhere name it with `--sysroot`, or set
  `PEPPER_SYSROOT_AARCH64_APPLE_IOS` (and
  `PEPPER_SYSROOT_AARCH64_APPLE_IOS_SIMULATOR`, and so on): the variable is
  named for the triple without its version. Homebrew's `llvm@20` does not
  ship `ld64.lld`: `brew install lld@20` (or `scripts/setup-llvm.sh`)
  installs it, and the link needs that `bin` folder and `llvm@20`'s on the
  PATH (see [Setting up LLVM](../contributing/setup.md)).
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

## Packaging for Xcode and SwiftPM

`--lib xcframework` builds the library for every iOS target at once, as one
`.xcframework` Xcode adds as a single dependency: a device slice and a
simulator slice holding both simulator architectures, each with the header
and a module map, so Swift imports it by name with no bridging header.
`--lib swift-package` puts it in a Swift package. Neither needs Xcode or an
SDK: the compiler builds each static library and writes the rest itself.

```sh
pepper build --lib xcframework greeter.pep -o Greeter.xcframework
pepper build --lib swift-package greeter.pep -o Greeter
```

The name comes from the output (`Greeter`): the module (`import Greeter`),
the library (`libGreeter.a`) and its header (`Greeter.h`). The second
writes:

```text
Greeter/
  Package.swift
  Greeter.xcframework/
    Info.plist
    ios-arm64/                    libGreeter.a, Headers/Greeter.h, Headers/module.modulemap
    ios-arm64_x86_64-simulator/   the same, its libGreeter.a holding arm64 and x86_64
```

In Xcode, drag `Greeter.xcframework` into the target's *Frameworks,
Libraries, and Embedded Content* (*Do Not Embed*: it is static), or add the
package with *Add Package Dependencies…* › *Add Local…*. A package depends
on it by path:

```swift
dependencies: [.package(path: "../Greeter")],
targets: [
    .target(name: "App", dependencies: [.product(name: "Greeter", package: "Greeter")]),
]
```

```swift
import Greeter

let result = "iOS".withCString { greet($0, strlen($0)) }!
defer { pepper_string_free(result) }
print(String(cString: result))
```

The slices are built for iOS 15 and later. A library that links others
(`[Link]`, `-l`) names them in its header, as `--lib static` does; the app
links them itself.

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
with the static library as an imported target, or add the `.aar` below.

## Packaging for Gradle

`--lib aar` builds the library as a shared library for every Android ABI
at once, as one Android library (`.aar`) a Gradle build adds as a single
dependency. It needs no Gradle and no JDK: the compiler builds each `.so`
with the NDK (found as for any Android link, above) and writes the archive
itself.

```sh
pepper build --lib aar greeter.pep -o greeter.aar
```

The name comes from the output (`greeter`, which takes letters, digits and
`_`): the library `libgreeter.so`, which Java loads with
`System.loadLibrary("greeter")`, its header `greeter.h`, and the manifest's
package, `pepper.greeter`. It holds:

```text
greeter.aar
  AndroidManifest.xml       minSdkVersion 30
  classes.jar, R.txt, res/  empty: the library has no Java code or resources
  include/greeter.h
  jni/arm64-v8a/libgreeter.so
  jni/x86_64/libgreeter.so
  LICENSE-OpenSSL.txt       only when the library imports tls (see Shipping)
```

Add it to the app module, and Gradle puts each ABI's `.so` in the APK:

```kotlin
dependencies {
    implementation(files("libs/greeter.aar"))
}
```

The `.so` holds only the Pepper code and its C functions, so the JNI
functions (`jni.c` above) go in a library of the app's own, built with the
NDK against `include/greeter.h` and linked with the `.aar`'s
`jni/<abi>/libgreeter.so` (`-L jni/<abi> -lgreeter`). Java loads that
library, and Android loads `libgreeter.so` first as its dependency.

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
- **TLS on iOS.** The `tls` module uses the system's Security.framework
  (Secure Transport), so `TlsConnector` and `http.Client`'s `https://` URLs
  work with nothing bundled: the server's certificate is checked against
  the system's roots and any added with `add_root_certificate`, and ALPN
  works. Secure Transport speaks TLS 1.2 at most, so a server that accepts
  only TLS 1.3 fails the handshake. A TLS server (`TlsAcceptor.create`) and
  a client certificate (`TlsConnector.set_identity`) return an `IoError`
  there for now. iOS checks a server's certificate more strictly than
  OpenSSL: it must name the host in its subject alternative names, carry the
  `serverAuth` extended key usage and, when issued after June 2019, be valid
  for at most 825 days, even from a private certificate authority.
- **TLS on Android.** Android ships no OpenSSL a program may load, so the
  toolchain carries a static OpenSSL 3 for each ABI
  (`runtime/tls/android/<triple>/libssl.a` and `libcrypto.a`), and a
  program that imports `tls` (or `http`) links it: `TlsConnector`,
  `TlsAcceptor` and `http.Client`'s `https://` URLs work as on Linux, TLS
  1.3 included. A connector trusts the system's certificate store (the
  Conscrypt module's, `/apex/com.android.conscrypt/cacerts`, on Android 14
  and later; `/system/etc/security/cacerts` before), less the certificates
  the user turned off in Settings, plus those the user installed
  (`/data/misc/user/0/cacerts-added`) where the process may read them, and
  any added with `add_root_certificate`. Unlike an app's Java networking,
  this ignores the app's network security configuration. OpenSSL adds
  about 4 MB to a stripped binary. An app linking a Pepper static
  library adds the libraries its header names (`-lssl -lcrypto`) from that
  folder: `-L <toolchain>/runtime/tls/android/aarch64-linux-android`.
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
- An Android library's thread-locals (its own and the runtime's) use the
  general-dynamic TLS model, since the app loads its `.so` with `dlopen`
  and bionic refuses initial-exec there; each access costs a call. A
  library for desktop Linux keeps initial-exec, which is faster but needs
  static TLS, so a `dlopen` of its `.so` may fail (see
  [Building the library](c-interop.md#building-the-library)).
- **OpenSSL's license.** An Android program or app that imports `tls` (or
  `http`) contains OpenSSL, which is under the Apache License 2.0, so it
  must give its users a copy of that license: ship
  `runtime/tls/android/LICENSE.txt` from the toolchain with it (a `--lib
  shared` build for Android writes it beside the `.so` as
  `LICENSE-OpenSSL.txt`, and `--lib aar` puts that in the `.aar`), as an app
  does in its open-source licenses screen (Google Play Services'
  `oss-licenses` plugin, or a page of the app's own), and say that the app
  includes OpenSSL. The iOS build bundles nothing.

## Debugging

`-g` writes DWARF, which LLDB reads in both Xcode and Android Studio. Build
the library with `-g` and the app in its debug configuration, and set
breakpoints in the `.pep` files by path.

## The prototype apps

`docs/examples/mobile/` holds a small app for each platform that calls the
same Pepper library, [`greeter.pep`](../../examples/mobile/greeter.pep):

- `ios/`: a SwiftUI app (`PepperDemo.swift`), and `build.sh`, which builds
  it with `swiftc` for the simulator and for devices, installs it in a
  booted simulator, launches it and checks its output; and `package/`, a
  Swift package whose tests `import Greeter` from the package `--lib
  swift-package` writes, which `package.sh` builds and runs in the
  simulator with `xcodebuild test`.
- `android/`: an activity in Java with the JNI functions in `jni.c`, and
  `build.sh`, which builds the APK with the Android SDK's own tools
  (`javac`, `d8`, `aapt2`, `apksigner`; Gradle is not needed), installs it
  in the emulator, starts it and checks its log. With
  `PEPPER_ANDROID_AAR=1` it builds the library with `--lib aar` instead,
  checks the `.aar`'s layout, and links `jni.c` against its
  `libgreeter.so`, which the APK carries beside it.

`scripts/mobile-test.sh` runs both on a Mac with Xcode and the Android SDK:
it builds every documentation example for the iOS simulator and for Android,
runs each in the simulator (`xcrun simctl spawn`) and in the emulator
(`adb shell`), then builds and runs the two apps, the Swift package's
tests, and the Android app again on the `.aar`. On iOS it also runs `scripts/mobile/tls_check.pep` in the simulator against `openssl s_server`
on the Mac, with a certificate authority made for the run: it trusts that
authority, connects to `localhost` and `127.0.0.1`, checks that ALPN chose
`http/1.1`, sends `GET /`, checks that a connector without the authority is
refused, and fetches the server through `http.Client`. It needs no internet
access. Set `PEPPER_MOBILE_TLS_URL` to an `https://` URL to also fetch that
public host through the system's roots. On Android the same check runs in
the emulator against the same kind of server, which `adb reverse` makes the
emulator's `localhost`, with the same opt-in public fetch. The Android run
also works on Linux, for the host's ABI (x86_64 there), as CI runs it:
`scripts/ci-provision-android.sh` sets up an emulator on a
GitHub-hosted Linux runner, since Apple silicon runners cannot run one.

```sh
bash scripts/mobile-test.sh target/bin/pep-build /tmp/mobile all
```

From a checkout, programs for Android that import `tls` need the static
OpenSSL in the runtime first, which the toolchain already carries:

```sh
bash scripts/openssl-android.sh fetch runtime
```

`scripts/openssl-android.sh build <ndk> <output-dir>` builds that archive
(OpenSSL 3.5, for each ABI, with the NDK's clang), and the
`openssl-android` workflow publishes it on the `openssl-<version>` release
whenever the version the script pins has not been published.

## Not supported yet

- **TLS on iOS**: servers, client certificates and TLS 1.3 (which need a
  SecIdentity and Network.framework).
- **Generated bindings**: the JNI layer and the Swift wrappers are written
  by hand; a generator could write them from the header.
- **Packaging**: `pep.toml` keys for `--lib xcframework` and `--lib aar`,
  an `.aar` for an API level other than 30, Mac Catalyst and macOS slices
  in the `.xcframework`, and `--lib jnilibs` (each ABI's `.so` laid out
  for Gradle's `jniLibs`).
- **Other targets**: 32-bit Android (`armeabi-v7a`, `x86`), Mac Catalyst,
  tvOS, watchOS and visionOS.
