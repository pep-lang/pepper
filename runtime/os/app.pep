## The folders an iOS or Android app keeps its files in.

import io;

## The folders of an iOS or Android app: where it keeps the files the user
## makes, what it can make again, and scratch files. Each is inside the
## app's own container, which only the app can write.
##
## @example
##     import io;
##     import os;
##
##     var folders = os.app_directories();
##     if (folders) {
##         io.File.write_text(folders.value().documents.join("notes.txt"), "kept");
##     }
export struct AppDirectories {
    ## The folder for the user's files, kept and backed up: iOS's
    ## `Documents`, Android's `Context.getFilesDir()`.
    const documents: io.Path;
    ## The folder for files the app can make again, which the system may
    ## remove when it runs short of space: iOS's `Library/Caches`, Android's
    ## `Context.getCacheDir()`.
    const cache: io.Path;
    ## The folder for scratch files: iOS's `tmp` (`NSTemporaryDirectory()`),
    ## and on Android the cache folder. `io.Directory.temp()` is the same
    ## folder.
    const temp: io.Path;

    ## Creates the folders.
    ##
    ## @param documents the folder for the user's files
    ## @param cache the folder for files the app can make again
    ## @param temp the folder for scratch files
    construct(documents: io.Path, cache: io.Path, temp: io.Path) {
        this.documents = documents;
        this.cache = cache;
        this.temp = temp;
    }
}

## Returns the app's folders on iOS and Android.
##
## On iOS they come from Foundation (`NSSearchPathForDirectoriesInDomains`
## and `NSTemporaryDirectory`), for an app and for a program the simulator
## runs. Android gives native code no way to find them, so the app passes
## them in first, through `pepper_set_app_directories` (see
## [iOS and Android](../language/mobile.md)); until it does there are none.
## Other systems have no app folders.
##
## @returns the folders, or none on another system, on Android before the
##   app passes them, and when Foundation cannot be opened
## @example
##     import os;
##
##     var folders = os.app_directories();
##     if (folders) {
##         print(folders.value().cache.to_string());
##     }
export app_directories(): AppDirectories? {
    return _os_app_directories();
}

[Target(!OS(IOS) && !OS(Android))]
_os_app_directories(): AppDirectories? {
    return Optional<AppDirectories>.Empty;
}

[Target(OS(Android))]
_os_app_directories(): AppDirectories? {
    __ptr<char> files = _pep_app_directory(0);
    __ptr<char> cache = _pep_app_directory(1);
    if (files == __null || cache == __null) {
        return Optional<AppDirectories>.Empty;
    }
    var cache_path = io.Path(String(cache));
    return Optional<AppDirectories>.Value(AppDirectories(io.Path(String(files)), cache_path, cache_path));
}

[Target(OS(IOS))]
extern void* dlopen(char* path, int flags);
[Target(OS(IOS))]
extern void* dlsym(void* handle, char* name);

# NSSearchPathDirectory values, and NSUserDomainMask.
const _OS_DOCUMENT_DIRECTORY: ulong = 9;
const _OS_CACHES_DIRECTORY: ulong = 13;
const _OS_USER_DOMAIN: ulong = 1;

# Foundation's answers, through the C functions it exports (an NSArray and
# an NSString are CFArray and CFString, toll-free bridged), opened with
# dlopen, as tls opens Security.framework, so that linking needs no
# `-framework`. They are autoreleased, so an autorelease pool around the
# calls frees them.
[Target(OS(IOS))]
_os_app_directories(): AppDirectories? {
    var foundation = dlopen("/System/Library/Frameworks/Foundation.framework/Foundation".c_str(), 2);  # RTLD_NOW
    var core = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation".c_str(), 2);
    var objc = dlopen("/usr/lib/libobjc.A.dylib".c_str(), 2);
    if (foundation == __null || core == __null || objc == __null) {
        return Optional<AppDirectories>.Empty;
    }
    var search = dlsym(
        foundation, "NSSearchPathForDirectoriesInDomains".c_str()
    ) as extern (ulong, ulong, u8) => __ptr<void>;
    var temporary = dlsym(foundation, "NSTemporaryDirectory".c_str()) as extern () => __ptr<void>;
    var count = dlsym(core, "CFArrayGetCount".c_str()) as extern (__ptr<void>) => long;
    var at = dlsym(core, "CFArrayGetValueAtIndex".c_str()) as extern (__ptr<void>, long) => __ptr<void>;
    var push = dlsym(objc, "objc_autoreleasePoolPush".c_str()) as extern () => __ptr<void>;
    var pop = dlsym(objc, "objc_autoreleasePoolPop".c_str()) as extern (__ptr<void>) => void;
    var to_c = dlsym(core, "CFStringGetCString".c_str()) as extern (__ptr<void>, __ptr<void>, long, uint) => u8;
    var pool = push();
    var paths = Array<String>();
    for (var directory in [_OS_DOCUMENT_DIRECTORY, _OS_CACHES_DIRECTORY]) {
        var found = search(directory, _OS_USER_DOMAIN, 1);
        paths.append(found != __null && count(found) > 0 ? _os_cf_string(to_c, at(found, 0)) : String());
    }
    paths.append(_os_cf_string(to_c, temporary()));
    pop(pool);
    if (paths.contains("")) {
        return Optional<AppDirectories>.Empty;
    }
    # NSTemporaryDirectory ends in '/'.
    var temp = paths[2].ends_with("/") ? paths[2].substr_bytes(0, paths[2].size - 1) : paths[2];
    return Optional<AppDirectories>.Value(AppDirectories(io.Path(paths[0]), io.Path(paths[1]), io.Path(temp)));
}

# The UTF-8 text of the CFString `text`, empty when it does not fit a path.
[Target(OS(IOS))]
_os_cf_string(to_c: extern (__ptr<void>, __ptr<void>, long, uint) => u8, text: __ptr<void>): String {
    if (text == __null) {
        return String();
    }
    # PATH_MAX, and kCFStringEncodingUTF8.
    __ptr<char> buffer = _pep_malloc(1024);
    var path = to_c(text, buffer, 1024, 134217984) != 0 ? String(buffer) : String();
    _pep_free(buffer);
    return path;
}
