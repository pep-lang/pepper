# The OpenSSL 3 that tls links on Android, under openssl.pep. Every
# declaration carries [Target(OS(Android))].
#
# Android ships no OpenSSL a program may load (its BoringSSL is private to
# the system), so a program for `--target *-android` that imports tls links
# a static OpenSSL built for its ABI: `android/<triple>/libssl.a` and
# `libcrypto.a` beside this file. scripts/openssl-android.sh builds them, the
# openssl-android workflow publishes them, and release-build.sh puts them in
# the toolchain's runtime (a checkout fetches them with that script).
#
# openssl.pep runs unchanged on top: its `_OpenSsl` asks `_tls_symbol` for
# each function by name, which here answers with the linked function
# instead of dlsym, and `libc.so` stands in for libssl as the library it
# opens. SSL_CTX_set_default_verify_paths would read the folder OpenSSL was
# built for, which Android lacks, so its name answers with
# `_tls_android_roots`, which loads Android's trusted roots instead.

import io;
import "openssl";

# The libraries, found beside this file for the target's ABI. libssl needs
# libcrypto after it.
[Target(OS(Android) && Arch(aarch64))]
[Link("ssl", path = "android/aarch64-linux-android")]
[Link("crypto")]
extern void TLS_client_method();
[Target(OS(Android) && Arch(x64))]
[Link("ssl", path = "android/x86_64-linux-android")]
[Link("crypto")]
extern void TLS_client_method();

# The other functions openssl.pep calls. Only their addresses are taken, so
# each is declared without its parameters.
[Target(OS(Android))]
extern void BIO_get_data();
[Target(OS(Android))]
extern void BIO_get_new_index();
[Target(OS(Android))]
extern void BIO_meth_new();
[Target(OS(Android))]
extern void BIO_meth_set_ctrl();
[Target(OS(Android))]
extern void BIO_meth_set_read();
[Target(OS(Android))]
extern void BIO_meth_set_write();
[Target(OS(Android))]
extern void BIO_new();
[Target(OS(Android))]
extern void BIO_set_data();
[Target(OS(Android))]
extern void BIO_set_init();
[Target(OS(Android))]
extern void ERR_clear_error();
[Target(OS(Android))]
extern void ERR_error_string_n();
[Target(OS(Android))]
extern void ERR_get_error();
[Target(OS(Android))]
extern void SSL_CTX_check_private_key();
[Target(OS(Android))]
extern void SSL_CTX_ctrl();
[Target(OS(Android))]
extern void SSL_CTX_free();
[Target(OS(Android))]
extern void SSL_CTX_get_ex_data();
[Target(OS(Android))]
extern void SSL_CTX_load_verify_locations();
[Target(OS(Android))]
extern void SSL_CTX_new();
[Target(OS(Android))]
extern void SSL_CTX_set_alpn_protos();
[Target(OS(Android))]
extern void SSL_CTX_set_alpn_select_cb();
[Target(OS(Android))]
extern void SSL_CTX_set_client_CA_list();
[Target(OS(Android))]
extern void SSL_CTX_set_ex_data();
[Target(OS(Android))]
extern void SSL_CTX_set_options();
[Target(OS(Android))]
extern void SSL_CTX_set_session_id_context();
[Target(OS(Android))]
extern void SSL_CTX_set_verify();
[Target(OS(Android))]
extern void SSL_CTX_use_PrivateKey_file();
[Target(OS(Android))]
extern void SSL_CTX_use_certificate_chain_file();
[Target(OS(Android))]
extern void SSL_accept();
[Target(OS(Android))]
extern void SSL_connect();
[Target(OS(Android))]
extern void SSL_ctrl();
[Target(OS(Android))]
extern void SSL_free();
[Target(OS(Android))]
extern void SSL_get0_alpn_selected();
[Target(OS(Android))]
extern void SSL_get0_param();
[Target(OS(Android))]
extern void SSL_get_error();
[Target(OS(Android))]
extern void SSL_get_verify_result();
[Target(OS(Android))]
extern void SSL_load_client_CA_file();
[Target(OS(Android))]
extern void SSL_new();
[Target(OS(Android))]
extern void SSL_read();
[Target(OS(Android))]
extern void SSL_select_next_proto();
[Target(OS(Android))]
extern void SSL_set1_host();
[Target(OS(Android))]
extern void SSL_set_bio();
[Target(OS(Android))]
extern void SSL_shutdown();
[Target(OS(Android))]
extern void SSL_write();
[Target(OS(Android))]
extern void TLS_server_method();
[Target(OS(Android))]
extern void X509_VERIFY_PARAM_set1_ip_asc();
[Target(OS(Android))]
extern void X509_verify_cert_error_string();

[Target(OS(Android))]
_tls_address(function: extern () => void): __ptr<void> {
    return function as __ptr<void>;
}

# The address of the OpenSSL function `name`; `handle` is unused.
#
# @panics when `name` is not in the table
[Target(OS(Android))]
_tls_symbol(handle: __ptr<void>, name: String): __ptr<void> {
    return match (name) {
        "SSL_CTX_set_default_verify_paths" => __function_pointer(_tls_android_roots),
        "TLS_client_method" => _tls_address(TLS_client_method),
        "BIO_get_data" => _tls_address(BIO_get_data),
        "BIO_get_new_index" => _tls_address(BIO_get_new_index),
        "BIO_meth_new" => _tls_address(BIO_meth_new),
        "BIO_meth_set_ctrl" => _tls_address(BIO_meth_set_ctrl),
        "BIO_meth_set_read" => _tls_address(BIO_meth_set_read),
        "BIO_meth_set_write" => _tls_address(BIO_meth_set_write),
        "BIO_new" => _tls_address(BIO_new),
        "BIO_set_data" => _tls_address(BIO_set_data),
        "BIO_set_init" => _tls_address(BIO_set_init),
        "ERR_clear_error" => _tls_address(ERR_clear_error),
        "ERR_error_string_n" => _tls_address(ERR_error_string_n),
        "ERR_get_error" => _tls_address(ERR_get_error),
        "SSL_CTX_check_private_key" => _tls_address(SSL_CTX_check_private_key),
        "SSL_CTX_ctrl" => _tls_address(SSL_CTX_ctrl),
        "SSL_CTX_free" => _tls_address(SSL_CTX_free),
        "SSL_CTX_get_ex_data" => _tls_address(SSL_CTX_get_ex_data),
        "SSL_CTX_load_verify_locations" => _tls_address(SSL_CTX_load_verify_locations),
        "SSL_CTX_new" => _tls_address(SSL_CTX_new),
        "SSL_CTX_set_alpn_protos" => _tls_address(SSL_CTX_set_alpn_protos),
        "SSL_CTX_set_alpn_select_cb" => _tls_address(SSL_CTX_set_alpn_select_cb),
        "SSL_CTX_set_client_CA_list" => _tls_address(SSL_CTX_set_client_CA_list),
        "SSL_CTX_set_ex_data" => _tls_address(SSL_CTX_set_ex_data),
        "SSL_CTX_set_options" => _tls_address(SSL_CTX_set_options),
        "SSL_CTX_set_session_id_context" => _tls_address(SSL_CTX_set_session_id_context),
        "SSL_CTX_set_verify" => _tls_address(SSL_CTX_set_verify),
        "SSL_CTX_use_PrivateKey_file" => _tls_address(SSL_CTX_use_PrivateKey_file),
        "SSL_CTX_use_certificate_chain_file" => _tls_address(SSL_CTX_use_certificate_chain_file),
        "SSL_accept" => _tls_address(SSL_accept),
        "SSL_connect" => _tls_address(SSL_connect),
        "SSL_ctrl" => _tls_address(SSL_ctrl),
        "SSL_free" => _tls_address(SSL_free),
        "SSL_get0_alpn_selected" => _tls_address(SSL_get0_alpn_selected),
        "SSL_get0_param" => _tls_address(SSL_get0_param),
        "SSL_get_error" => _tls_address(SSL_get_error),
        "SSL_get_verify_result" => _tls_address(SSL_get_verify_result),
        "SSL_load_client_CA_file" => _tls_address(SSL_load_client_CA_file),
        "SSL_new" => _tls_address(SSL_new),
        "SSL_read" => _tls_address(SSL_read),
        "SSL_select_next_proto" => _tls_address(SSL_select_next_proto),
        "SSL_set1_host" => _tls_address(SSL_set1_host),
        "SSL_set_bio" => _tls_address(SSL_set_bio),
        "SSL_shutdown" => _tls_address(SSL_shutdown),
        "SSL_write" => _tls_address(SSL_write),
        "TLS_server_method" => _tls_address(TLS_server_method),
        "X509_VERIFY_PARAM_set1_ip_asc" => _tls_address(X509_VERIFY_PARAM_set1_ip_asc),
        "X509_verify_cert_error_string" => _tls_address(X509_verify_cert_error_string),
        else => _tls_android_missing(name),
    };
}

# A function openssl.pep asks for that the table above lacks: a call
# through the null it would get would crash far from the cause.
[Target(OS(Android))]
_tls_android_missing(name: String): __ptr<void> {
    panic($"tls: openssl_android.pep does not link the OpenSSL function '{name}'");
    return __null;
}

# The library openssl.pep opens to mark OpenSSL as there: any that loads.
[Target(OS(Android))]
_tls_openssl_paths(): String[] {
    return ["libc.so"];
}

# Android's trusted roots, loaded into `context` in place of
# SSL_CTX_set_default_verify_paths: every certificate of the system's store
# (the Conscrypt module's on Android 14 and later, which updates apart from
# the system) but those the user turned off in Settings, and those the user
# added, where this process may read them. Each file is loaded whole: they
# are named for OpenSSL's old subject hash, which OpenSSL 3's hashed-folder
# lookup does not read.
# shortcut: parses the whole store (about 150 files) for each client
# context; share one X509_STORE if making contexts shows in a profile.
[Target(OS(Android))]
_tls_android_roots(context: __ptr<void>): int {
    var load = _tls_openssl.get()._context_load_roots;
    var system = io.Path("/apex/com.android.conscrypt/cacerts");
    if (!system.is_directory()) {
        system = io.Path("/system/etc/security/cacerts");
    }
    var removed = Array<String>();
    for (var entry in _tls_android_files(io.Path("/data/misc/user/0/cacerts-removed"))) {
        removed.append(entry.name);
    }
    var files = Array<io.DirEntry>();
    for (var entry in _tls_android_files(system)) {
        if (!removed.contains(entry.name)) {
            files.append(entry);
        }
    }
    files.append_all(_tls_android_files(io.Path("/data/misc/user/0/cacerts-added")));
    for (var entry in files) {
        var path = entry.path.to_string();
        load(context, path.c_str(), __null);
    }
    return 1;
}

# The files in `folder`, or none when it cannot be read.
[Target(OS(Android))]
_tls_android_files(folder: io.Path): io.DirEntry[] {
    var files = Array<io.DirEntry>();
    var directory = io.Directory.open(folder);
    if (directory.is_ok()) {
        var entries = directory.value().entries();
        if (entries.is_ok()) {
            for (var entry in entries.value()) {
                if (entry.is_file) {
                    files.append(entry);
                }
            }
        }
    }
    return files;
}
