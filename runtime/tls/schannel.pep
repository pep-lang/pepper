# The SChannel layer for tls on Windows. Every declaration carries
# [Target(OS(Windows))]; openssl.pep and wasi.pep declare the same
# `_tls_sys_*` functions for Linux and macOS, and for WASI.
#
# SChannel (SSPI) does no I/O: the handshake loop, DecryptMessage and
# EncryptMessage work on buffers, and this layer moves the bytes with the io
# socket layer (`_io_sys_socket_receive` / `_send`), which parks a task when
# the socket would block. TLS 1.2 is the minimum.
#
# A client identity (mutual TLS) is a certificate and key loaded as a
# server's are (below), passed in the client's credential; the server asks
# for it with ASC_REQ_MUTUAL_AUTH and, after the handshake, checks the
# client's chain against only the roots given (a chain engine with
# hExclusiveRoot) with CERT_CHAIN_POLICY_SSL for a client.
#
# The client checks the server's certificate itself
# (SCH_CRED_MANUAL_CRED_VALIDATION) after the handshake: the chain is built
# against the system's roots and, when that fails and roots were added, again
# against only the added roots (a chain engine with hExclusiveRoot); then
# CertVerifyCertificateChainPolicy(CERT_CHAIN_POLICY_SSL) checks the chain
# and the host name.
#
# A private key (PEM, PKCS #8), a server's or a client's, is imported into
# the current user's Software Key Storage Provider under a name unique to
# the process, because SChannel reaches a key by name; freeing the context
# deletes it.
#
# Layouts (x64): SecBuffer { u32 cbBuffer; u32 BufferType; void* pvBuffer }
# is 16 bytes; SecBufferDesc { u32 ulVersion; u32 cBuffers; SecBuffer* } is
# 16; a CredHandle or CtxtHandle is 16. SCH_CREDENTIALS (version 5) is 72
# bytes: dwVersion 0, dwCredFormat 4, cCreds 8, paCred 16, hRootStore 24,
# cMappers 32, aphMappers 40, dwSessionLifespan 48, dwFlags 52,
# cTlsParameters 56, pTlsParameters 64. TLS_PARAMETERS is 40 bytes with
# grbitDisabledProtocols at 16.
#
# A context is a malloc'd block (`_TLS_CONTEXT_SIZE`): the credential handle
# at 0, then (8-byte words) whether it is a server's at 16, the store of
# added roots (client) or of the chain (server) at 24, the certificate it
# presents at 32 and its key's name (UTF-16) at 40 (null for a client with
# no identity), and a server's store of roots for client certificates at 48
# (null when clients are not asked for one).
#
# A session is a malloc'd block (`_TLS_SESSION_SIZE`): the security context
# handle at 0, then the socket at 16, its context at 24, the received but not
# yet decrypted bytes (buffer 32, count 40), the decrypted bytes not yet read
# (buffer 48, start 56, end 64), the stream sizes (header 72, trailer 76,
# largest message 80, as u32), whether the peer closed at 88, and the host
# name (UTF-16, client only) at 96.

import async;
import io;

# ── C functions (secur32, crypt32, ncrypt, kernel32) ─────────────────────────

[Target(OS(Windows))]
[Link("secur32")]
extern int AcquireCredentialsHandleW(
    void* principal,
    void* package,
    uint use,
    void* logon,
    void* data,
    void* key,
    void* argument,
    void* credential,
    void* expiry
);
[Target(OS(Windows))]
[Link("secur32")]
extern int InitializeSecurityContextW(
    void* credential,
    void* context,
    void* target,
    uint request,
    uint reserved1,
    uint representation,
    void* input,
    uint reserved2,
    void* new_context,
    void* output,
    void* attributes,
    void* expiry
);
[Target(OS(Windows))]
[Link("secur32")]
extern int AcceptSecurityContext(
    void* credential,
    void* context,
    void* input,
    uint request,
    uint representation,
    void* new_context,
    void* output,
    void* attributes,
    void* expiry
);
[Target(OS(Windows))]
[Link("secur32")]
extern int DeleteSecurityContext(void* context);
[Target(OS(Windows))]
[Link("secur32")]
extern int FreeCredentialsHandle(void* credential);
[Target(OS(Windows))]
[Link("secur32")]
extern int FreeContextBuffer(void* buffer);
[Target(OS(Windows))]
[Link("secur32")]
extern int QueryContextAttributesW(void* context, uint attribute, void* buffer);
[Target(OS(Windows))]
[Link("secur32")]
extern int EncryptMessage(void* context, uint quality, void* message, uint sequence);
[Target(OS(Windows))]
[Link("secur32")]
extern int DecryptMessage(void* context, void* message, uint sequence, void* quality);
[Target(OS(Windows))]
[Link("secur32")]
extern int ApplyControlToken(void* context, void* input);

[Target(OS(Windows))]
[Link("crypt32")]
extern void* CertOpenStore(ulong provider, uint encoding, void* crypt, uint flags, void* parameter);
[Target(OS(Windows))]
[Link("crypt32")]
extern int CertCloseStore(void* store, uint flags);
[Target(OS(Windows))]
[Link("crypt32")]
extern int CertAddEncodedCertificateToStore(
    void* store, uint encoding, void* data, uint size, uint disposition, void* added
);
[Target(OS(Windows))]
[Link("crypt32")]
extern int CertFreeCertificateContext(void* certificate);
[Target(OS(Windows))]
[Link("crypt32")]
extern int CertSetCertificateContextProperty(void* certificate, uint property, uint flags, void* data);
[Target(OS(Windows))]
[Link("crypt32")]
extern int CertGetCertificateChain(
    void* engine,
    void* certificate,
    void* time,
    void* additional,
    void* parameters,
    uint flags,
    void* reserved,
    void* chain
);
[Target(OS(Windows))]
[Link("crypt32")]
extern void CertFreeCertificateChain(void* chain);
[Target(OS(Windows))]
[Link("crypt32")]
extern int CertVerifyCertificateChainPolicy(ulong policy, void* chain, void* parameters, void* status);
[Target(OS(Windows))]
[Link("crypt32")]
extern int CertCreateCertificateChainEngine(void* config, void* engine);
[Target(OS(Windows))]
[Link("crypt32")]
extern void CertFreeCertificateChainEngine(void* engine);
[Target(OS(Windows))]
[Link("crypt32")]
extern int CryptStringToBinaryA(char* text, uint length, uint flags, void* binary, void* size, void* skip, void* used);

[Target(OS(Windows))]
[Link("ncrypt")]
extern int NCryptOpenStorageProvider(void* provider, void* name, uint flags);
[Target(OS(Windows))]
[Link("ncrypt")]
extern int NCryptImportKey(
    ulong provider, ulong import_key, void* blob_type, void* parameters, void* key, void* data, uint size, uint flags
);
[Target(OS(Windows))]
[Link("ncrypt")]
extern int NCryptFinalizeKey(ulong key, uint flags);
[Target(OS(Windows))]
[Link("ncrypt")]
extern int NCryptOpenKey(ulong provider, void* key, void* name, uint key_spec, uint flags);
[Target(OS(Windows))]
[Link("ncrypt")]
extern int NCryptDeleteKey(ulong key, uint flags);
[Target(OS(Windows))]
[Link("ncrypt")]
extern int NCryptFreeObject(ulong handle);

[Target(OS(Windows))]
extern uint GetCurrentProcessId();

# ── Constants ────────────────────────────────────────────────────────────────

const _TLS_CONTEXT_SIZE: ulong = 56;
const _TLS_SESSION_SIZE: ulong = 104;
# The receive and plaintext buffers: room for any TLS record and most
# handshake flights.
const _TLS_BUFFER_SIZE: ulong = 65536;

# SECURITY_STATUS values.
const _TLS_SEC_E_OK: int = 0;
const _TLS_SEC_I_CONTINUE_NEEDED: int = 590610;          # 0x00090312
const _TLS_SEC_I_CONTEXT_EXPIRED: int = 590615;          # 0x00090317
const _TLS_SEC_I_INCOMPLETE_CREDENTIALS: int = 590624;   # 0x00090320
const _TLS_SEC_I_RENEGOTIATE: int = 590625;              # 0x00090321
const _TLS_SEC_E_INCOMPLETE_MESSAGE: int = -2146893032;  # 0x80090318

# SecBuffer types.
const _TLS_BUFFER_EMPTY: uint = 0;
const _TLS_BUFFER_DATA: uint = 1;
const _TLS_BUFFER_TOKEN: uint = 2;
const _TLS_BUFFER_EXTRA: uint = 5;
const _TLS_BUFFER_TRAILER: uint = 6;
const _TLS_BUFFER_HEADER: uint = 7;

# ISC_REQ_SEQUENCE_DETECT | REPLAY_DETECT | CONFIDENTIALITY | ALLOCATE_MEMORY
# | EXTENDED_ERROR | STREAM | MANUAL_CRED_VALIDATION.
const _TLS_CLIENT_REQUEST: uint = 573724;
# ASC_REQ_SEQUENCE_DETECT | REPLAY_DETECT | CONFIDENTIALITY | ALLOCATE_MEMORY
# | EXTENDED_ERROR | STREAM.
const _TLS_SERVER_REQUEST: uint = 98588;
# ASC_REQ_MUTUAL_AUTH: ask the client for a certificate.
const _TLS_SERVER_MUTUAL: uint = 2;

# SCH_CRED_MANUAL_CRED_VALIDATION | SCH_CRED_NO_DEFAULT_CREDS |
# SCH_USE_STRONG_CRYPTO, and SCH_CRED_NO_SYSTEM_MAPPER (a client
# certificate is not mapped to a Windows account) | SCH_USE_STRONG_CRYPTO.
const _TLS_CLIENT_CREDENTIAL_FLAGS: uint = 4194328;
const _TLS_SERVER_CREDENTIAL_FLAGS: uint = 4194306;
# SSL 2 and 3, TLS 1.0 and 1.1, client and server.
const _TLS_DISABLED_PROTOCOLS: uint = 1020;

# X509_ASN_ENCODING | PKCS_7_ASN_ENCODING.
const _TLS_ENCODING: uint = 65537;

# ── Errors ───────────────────────────────────────────────────────────────────

# ERROR_INVALID_DATA: the code of every TLS error.
[Target(OS(Windows))]
_tls_sys_code_protocol(): io.ErrorCode { return 13; }

[Target(OS(Windows))]
_tls_error(message: String): io.IoError {
    return io.IoError(_tls_sys_code_protocol(), message);
}

# `what` and the status in hexadecimal.
[Target(OS(Windows))]
_tls_status_error(what: String, status: int): io.IoError {
    return _tls_error($"{what} ({_tls_hex(status as uint)})");
}

[Target(OS(Windows))]
_tls_hex(value: uint): String {
    return $"0x{value:08x}";
}

# Why the certificate check failed, from CERT_CHAIN_POLICY_STATUS.dwError.
[Target(OS(Windows))]
_tls_certificate_reason(error: uint): String {
    return match (error) {
        2148204809 => "self-signed certificate or untrusted root",  # CERT_E_UNTRUSTEDROOT
        2148204815 => "the certificate is not for this host",       # CERT_E_CN_NO_MATCH
        2148204801 => "certificate has expired",                    # CERT_E_EXPIRED
        2148204810 => "unable to get local issuer certificate",     # CERT_E_CHAINING
        2148204812 => "certificate revoked",                        # CERT_E_REVOKED
        2148204814 => "unsupported certificate purpose",            # CERT_E_WRONG_USAGE
        else => $"error {_tls_hex(error)}",
    };
}

# ── Memory helpers ───────────────────────────────────────────────────────────

[Target(OS(Windows))]
_tls_u32(block: __ptr<u8>, offset: ulong): uint {
    return unsafe_cast<__ptr<uint>>(block + offset)[0];
}

[Target(OS(Windows))]
_tls_set_u32(block: __ptr<u8>, offset: ulong, value: uint) {
    unsafe_cast<__ptr<uint>>(block + offset)[0] = value;
}

[Target(OS(Windows))]
_tls_word(block: __ptr<u8>, offset: ulong): ulong {
    return unsafe_cast<__ptr<ulong>>(block + offset)[0];
}

[Target(OS(Windows))]
_tls_set_word(block: __ptr<u8>, offset: ulong, value: ulong) {
    unsafe_cast<__ptr<ulong>>(block + offset)[0] = value;
}

[Target(OS(Windows))]
_tls_pointer(block: __ptr<u8>, offset: ulong): __ptr<u8> {
    return unsafe_cast<__ptr<__ptr<u8>>>(block + offset)[0];
}

[Target(OS(Windows))]
_tls_set_pointer(block: __ptr<u8>, offset: ulong, value: __ptr<u8>) {
    unsafe_cast<__ptr<__ptr<u8>>>(block + offset)[0] = value;
}

# Copies `n` bytes from `source` to `destination`, front to back (so it may
# move bytes toward the start of the same buffer).
[Target(OS(Windows))]
_tls_copy(destination: __ptr<u8>, source: __ptr<u8>, n: ulong) {
    ulong i = 0;
    while (i < n) {
        destination[i] = source[i];
        i = i + 1;
    }
}

# Sets SecBuffer `index` of the array at `buffers`.
[Target(OS(Windows))]
_tls_set_buffer(buffers: __ptr<u8>, index: ulong, kind: uint, data: __ptr<u8>, size: ulong) {
    var buffer = buffers + index * 16;
    _tls_set_u32(buffer, 0, size as uint);
    _tls_set_u32(buffer, 4, kind);
    _tls_set_pointer(buffer, 8, data);
}

# A SecBufferDesc (16 bytes) followed by `count` SecBuffers, all empty.
[Target(OS(Windows))]
_tls_buffers(count: ulong): __ptr<u8> {
    __ptr<u8> desc = _pep_malloc(16 + count * 16);
    _tls_set_u32(desc, 0, 0);  # SECBUFFER_VERSION
    _tls_set_u32(desc, 4, count as uint);
    _tls_set_pointer(desc, 8, desc + 16);
    return desc;
}

[Target(OS(Windows))]
_tls_buffer_at(desc: __ptr<u8>, index: ulong): __ptr<u8> {
    return desc + 16 + index * 16;
}

# ── Certificates and keys ────────────────────────────────────────────────────

# The DER bytes of every PEM block labeled `label` in `text`.
[Target(OS(Windows))]
_tls_pem_blocks(text: String, label: String): Array<u8[]> {
    var blocks = Array<u8[]>();
    var begin = $"-----BEGIN {label}-----";
    var end = $"-----END {label}-----";
    ulong from = 0;
    while (true) {
        var start = text.find(begin, from);
        if (start < 0) {
            return blocks;
        }
        var stop = text.find(end, start as ulong);
        if (stop < 0) {
            return blocks;
        }
        var block_end = stop as ulong + end.size;
        var block = text.substr_bytes(start as ulong, block_end - start as ulong);
        __ptr<uint> size = _pep_malloc(4);
        size[0] = 0;
        # CRYPT_STRING_BASE64HEADER
        if (CryptStringToBinaryA(block.c_str(), block.size as uint, 0, __null, size, __null, __null) != 0) {
            var der = Array<u8>(size[0] as ulong);
            der.reserve(size[0] as ulong);
            if (CryptStringToBinaryA(block.c_str(), block.size as uint, 0, der._data, size, __null, __null) != 0) {
                der._size = size[0] as ulong;
                blocks.append(der);
            }
        }
        _pep_free(size);
        from = block_end;
    }
    return blocks;
}

[Target(OS(Windows))]
_tls_read_text(path: io.Path, what: String): io.IoResult<String> {
    var text = io.File.read_to_string(path);
    if (text.is_err()) {
        return io.IoResult<String>.err(_tls_error($"cannot read {what} '{path}': {text.error().message}"));
    }
    return text;
}

# Adds the DER certificate to `store`; the added context through `added`
# when it is not null.
[Target(OS(Windows))]
_tls_add_certificate(store: __ptr<void>, der: u8[], added: __ptr<__ptr<void>>): bool {
    # CERT_STORE_ADD_ALWAYS
    return CertAddEncodedCertificateToStore(store, _TLS_ENCODING, der._data, der._size as uint, 4, added) != 0;
}

# A new in-memory certificate store (CERT_STORE_PROV_MEMORY).
[Target(OS(Windows))]
_tls_memory_store(): __ptr<void> {
    return CertOpenStore(2, 0, __null, 0, __null);
}

# ── Credentials ──────────────────────────────────────────────────────────────

# Acquires a credential handle into the 16 bytes at `context` with
# SChannel's SCH_CREDENTIALS; `certificate` is the one to present (null for
# a client with no identity).
[Target(OS(Windows))]
_tls_acquire(context: __ptr<u8>, server: bool, certificate: __ptr<void>): int {
    __ptr<u8> credentials = _pep_malloc(72);
    __ptr<u8> parameters = _pep_malloc(40);
    __ptr<__ptr<void>> certificates = _pep_malloc(8);
    certificates[0] = certificate;
    _tls_set_u32(credentials, 0, 5);  # SCH_CREDENTIALS_VERSION
    _tls_set_u32(parameters, 16, _TLS_DISABLED_PROTOCOLS);
    _tls_set_u32(credentials, 56, 1);
    _tls_set_pointer(credentials, 64, parameters);
    if (certificate != __null) {
        _tls_set_u32(credentials, 8, 1);
        _tls_set_pointer(credentials, 16, unsafe_cast<__ptr<u8>>(certificates));
    }
    uint use = 2;  # SECPKG_CRED_OUTBOUND
    if (server) {
        use = 1;  # SECPKG_CRED_INBOUND
        _tls_set_u32(credentials, 52, _TLS_SERVER_CREDENTIAL_FLAGS);
    } else {
        _tls_set_u32(credentials, 52, _TLS_CLIENT_CREDENTIAL_FLAGS);
    }
    var package = io._io_win_wide("Microsoft Unified Security Protocol Provider");
    __ptr<u8> expiry = _pep_malloc(8);
    var status = AcquireCredentialsHandleW(__null, package, use, __null, credentials, __null, __null, context, expiry);
    _pep_free(expiry);
    _pep_free(package);
    _pep_free(certificates);
    _pep_free(parameters);
    _pep_free(credentials);
    return status;
}

# A client context that checks the server's certificate against the
# system's trusted roots (and any added with `_tls_sys_add_root`).
[Target(OS(Windows))]
_tls_sys_client_context(): io.IoResult<__ptr<void>> {
    __ptr<u8> context = _pep_malloc(_TLS_CONTEXT_SIZE);
    var status = _tls_acquire(context, false, __null);
    if (status != _TLS_SEC_E_OK) {
        _pep_free(context);
        return io.IoResult<__ptr<void>>.err(_tls_status_error("cannot create a TLS context", status));
    }
    _tls_set_word(context, 16, 0);
    _tls_set_pointer(context, 24, _tls_memory_store() as __ptr<u8>);
    return io.IoResult<__ptr<void>>.ok(context);
}

# The key storage provider (MS_KEY_STORAGE_PROVIDER), or 0.
[Target(OS(Windows))]
_tls_key_provider(): ulong {
    __ptr<ulong> provider = _pep_malloc(8);
    provider[0] = 0;
    var name = io._io_win_wide("Microsoft Software Key Storage Provider");
    NCryptOpenStorageProvider(provider, name, 0);
    _pep_free(name);
    var result = provider[0];
    _pep_free(provider);
    return result;
}

# Numbers the server keys this process imports.
const _tls_key_count = async.Atomic<ulong>(0);

# Imports the PKCS #8 key under a new name; the name, or an error.
[Target(OS(Windows))]
_tls_import_key(der: u8[]): io.IoResult<__ptr<u16>> {
    var provider = _tls_key_provider();
    if (provider == 0) {
        return io.IoResult<__ptr<u16>>.err(_tls_error("cannot open the key storage provider"));
    }
    var number = _tls_key_count.fetch_add(1);
    var name = io._io_win_wide($"pepper-tls-{GetCurrentProcessId() as ulong}-{number}");
    # NCryptBufferDesc { version, count, buffers } with one NCryptBuffer
    # { cbBuffer, BufferType = NCRYPTBUFFER_PKCS_KEY_NAME, pvBuffer }: the
    # same layout as SecBufferDesc and SecBuffer.
    var desc = _tls_buffers(1);
    _tls_set_buffer(desc + 16, 0, 45, unsafe_cast<__ptr<u8>>(name), ((io._io_win_wide_len(name) as ulong) + 1) * 2);
    var blob_type = io._io_win_wide("PKCS8_PRIVATEKEY");
    __ptr<ulong> key = _pep_malloc(8);
    key[0] = 0;
    # NCRYPT_OVERWRITE_KEY_FLAG | NCRYPT_DO_NOT_FINALIZE_FLAG
    var status = NCryptImportKey(provider, 0, blob_type, desc, key, der._data, der._size as uint, 1152);
    if (status == 0) {
        status = NCryptFinalizeKey(key[0], 0);
    }
    if (key[0] != 0) {
        NCryptFreeObject(key[0]);
    }
    _pep_free(key);
    _pep_free(blob_type);
    _pep_free(desc);
    NCryptFreeObject(provider);
    if (status != 0) {
        _pep_free(name);
        return io.IoResult<__ptr<u16>>.err(_tls_status_error("cannot import the private key", status));
    }
    return io.IoResult<__ptr<u16>>.ok(name);
}

# Deletes the imported key `name`.
[Target(OS(Windows))]
_tls_delete_key(name: __ptr<u16>) {
    var provider = _tls_key_provider();
    if (provider == 0) {
        return;
    }
    __ptr<ulong> key = _pep_malloc(8);
    key[0] = 0;
    if (NCryptOpenKey(provider, key, name, 0, 0) == 0) {
        NCryptDeleteKey(key[0], 0);  # frees the handle too
    }
    _pep_free(key);
    NCryptFreeObject(provider);
}

# The certificate chain and private key in PEM files, loaded for SChannel:
# a store holding the chain, the first certificate's context, with its key
# imported under the returned name and linked to it.
[Target(OS(Windows))]
_tls_load_identity(chain: io.Path, key: io.Path): io.IoResult<(__ptr<void>, __ptr<void>, __ptr<u16>)> {
    var chain_text = _tls_read_text(chain, "the certificate chain");
    if (chain_text.is_err()) {
        return io.IoResult<(__ptr<void>, __ptr<void>, __ptr<u16>)>.err(chain_text.error());
    }
    var certificates = _tls_pem_blocks(chain_text.value(), "CERTIFICATE");
    if (certificates.count == 0) {
        return io.IoResult<(__ptr<void>, __ptr<void>, __ptr<u16>)>.err(
            _tls_error($"cannot load the certificate chain '{chain}': no certificate in it")
        );
    }
    var key_text = _tls_read_text(key, "the private key");
    if (key_text.is_err()) {
        return io.IoResult<(__ptr<void>, __ptr<void>, __ptr<u16>)>.err(key_text.error());
    }
    var keys = _tls_pem_blocks(key_text.value(), "PRIVATE KEY");
    if (keys.count == 0) {
        return io.IoResult<(__ptr<void>, __ptr<void>, __ptr<u16>)>.err(
            _tls_error($"cannot load the private key '{key}': no PKCS #8 PRIVATE KEY block in it")
        );
    }
    var store = _tls_memory_store();
    __ptr<__ptr<void>> leaf = _pep_malloc(8);
    leaf[0] = __null;
    var loaded = _tls_add_certificate(store, certificates[0], leaf);
    ulong i = 1;
    while (loaded && i < certificates.count) {
        loaded = _tls_add_certificate(store, certificates[i], __null);
        i = i + 1;
    }
    var certificate = leaf[0];
    _pep_free(leaf);
    if (!loaded) {
        if (certificate != __null) {
            CertFreeCertificateContext(certificate);
        }
        CertCloseStore(store, 0);
        return io.IoResult<(__ptr<void>, __ptr<void>, __ptr<u16>)>.err(
            _tls_error($"cannot load the certificate chain '{chain}'")
        );
    }
    var imported = _tls_import_key(keys[0]);
    if (imported.is_err()) {
        CertFreeCertificateContext(certificate);
        CertCloseStore(store, 0);
        return io.IoResult<(__ptr<void>, __ptr<void>, __ptr<u16>)>.err(imported.error());
    }
    var name = imported.value();
    # CRYPT_KEY_PROV_INFO { container, provider, type, flags, cProvParam,
    # rgProvParam, dwKeySpec }: 48 bytes.
    __ptr<u8> info = _pep_malloc(48);
    var provider_name = io._io_win_wide("Microsoft Software Key Storage Provider");
    _tls_set_pointer(info, 0, unsafe_cast<__ptr<u8>>(name));
    _tls_set_pointer(info, 8, unsafe_cast<__ptr<u8>>(provider_name));
    CertSetCertificateContextProperty(certificate, 2, 0, info);  # CERT_KEY_PROV_INFO_PROP_ID
    _pep_free(provider_name);
    _pep_free(info);
    return io.IoResult<(__ptr<void>, __ptr<void>, __ptr<u16>)>.ok((store, certificate, name));
}

# Frees what `_tls_load_identity` returned: deletes the key, frees the
# certificate and closes the store (null when already closed).
[Target(OS(Windows))]
_tls_free_identity(store: __ptr<void>, certificate: __ptr<void>, name: __ptr<u16>) {
    _tls_delete_key(name);
    _pep_free(name);
    CertFreeCertificateContext(certificate);
    if (store != __null) {
        CertCloseStore(store, 0);
    }
}

# A server context presenting the PEM certificate chain and private key.
[Target(OS(Windows))]
_tls_sys_server_context(chain: io.Path, key: io.Path): io.IoResult<__ptr<void>> {
    var loaded = _tls_load_identity(chain, key);
    if (loaded.is_err()) {
        return io.IoResult<__ptr<void>>.err(loaded.error());
    }
    var (store, certificate, name) = loaded.value();
    __ptr<u8> context = _pep_malloc(_TLS_CONTEXT_SIZE);
    var status = _tls_acquire(context, true, certificate);
    if (status != _TLS_SEC_E_OK) {
        _pep_free(context);
        _tls_free_identity(store, certificate, name);
        return io.IoResult<__ptr<void>>.err(_tls_status_error("cannot use the certificate and key", status));
    }
    _tls_set_word(context, 16, 1);
    _tls_set_pointer(context, 24, store as __ptr<u8>);
    _tls_set_pointer(context, 32, certificate as __ptr<u8>);
    _tls_set_pointer(context, 40, unsafe_cast<__ptr<u8>>(name));
    return io.IoResult<__ptr<void>>.ok(context);
}

# Makes a client context present the PEM certificate chain and private key
# to servers that ask for one: acquires a new credential with the
# certificate and frees the old one, and any identity it had.
[Target(OS(Windows))]
_tls_sys_set_identity(context: __ptr<void>, chain: io.Path, key: io.Path): io.IoResult<void> {
    var loaded = _tls_load_identity(chain, key);
    if (loaded.is_err()) {
        return io.IoResult<void>.err(loaded.error());
    }
    var (store, certificate, name) = loaded.value();
    __ptr<u8> credential = _pep_malloc(16);
    var status = _tls_acquire(credential, false, certificate);
    if (status != _TLS_SEC_E_OK) {
        _pep_free(credential);
        _tls_free_identity(store, certificate, name);
        return io.IoResult<void>.err(_tls_status_error("cannot use the certificate and key", status));
    }
    # The certificate keeps its store, with the intermediates SChannel
    # sends, until it is freed.
    CertCloseStore(store, 0);
    __ptr<u8> block = context;
    FreeCredentialsHandle(block);
    _tls_copy(block, credential, 16);
    _pep_free(credential);
    var old_certificate = _tls_pointer(block, 32);
    if (old_certificate != __null) {
        _tls_free_identity(__null, old_certificate as __ptr<void>, unsafe_cast<__ptr<u16>>(_tls_pointer(block, 40)));
    }
    _tls_set_pointer(block, 32, certificate as __ptr<u8>);
    _tls_set_pointer(block, 40, unsafe_cast<__ptr<u8>>(name));
    return io.IoResult<void>.ok();
}

# The certificates in the PEM file at `path`, added to `store`.
[Target(OS(Windows))]
_tls_add_certificates(store: __ptr<void>, path: io.Path): io.IoResult<void> {
    var text = _tls_read_text(path, "the certificates");
    if (text.is_err()) {
        return io.IoResult<void>.err(text.error());
    }
    var certificates = _tls_pem_blocks(text.value(), "CERTIFICATE");
    if (certificates.count == 0) {
        return io.IoResult<void>.err(_tls_error($"cannot load the certificates in '{path}': none found"));
    }
    for (var der in certificates) {
        if (!_tls_add_certificate(store, der, __null)) {
            return io.IoResult<void>.err(_tls_error($"cannot load the certificates in '{path}'"));
        }
    }
    return io.IoResult<void>.ok();
}

# Makes a server context ask every client for a certificate issued by one in
# the PEM file `roots`, and fail the handshake without one.
[Target(OS(Windows))]
_tls_sys_require_client_certificate(context: __ptr<void>, roots: io.Path): io.IoResult<void> {
    __ptr<u8> block = context;
    var store = _tls_pointer(block, 48) as __ptr<void>;
    var created = store == __null;
    if (created) {
        store = _tls_memory_store();
    }
    var added = _tls_add_certificates(store, roots);
    if (added.is_err()) {
        if (created) {
            CertCloseStore(store, 0);
        }
        return added;
    }
    _tls_set_pointer(block, 48, store as __ptr<u8>);
    return io.IoResult<void>.ok();
}

# Also trusts the PEM certificates in `path`.
[Target(OS(Windows))]
_tls_sys_add_root(context: __ptr<void>, path: io.Path): io.IoResult<void> {
    return _tls_add_certificates(_tls_pointer(context as __ptr<u8>, 24) as __ptr<void>, path);
}

[Target(OS(Windows))]
_tls_sys_context_free(context: __ptr<void>) {
    __ptr<u8> block = context;
    FreeCredentialsHandle(block);
    var store = _tls_pointer(block, 24);
    var certificate = _tls_pointer(block, 32);
    if (certificate != __null) {
        _tls_free_identity(__null, certificate as __ptr<void>, unsafe_cast<__ptr<u16>>(_tls_pointer(block, 40)));
    }
    if (store != __null) {
        CertCloseStore(store, 0);
    }
    var client_roots = _tls_pointer(block, 48);
    if (client_roots != __null) {
        CertCloseStore(client_roots, 0);
    }
    _pep_free(block);
}

# ── Sessions ─────────────────────────────────────────────────────────────────

[Target(OS(Windows))]
_tls_session_new(context: __ptr<void>, h: io.SocketHandle, host: String): __ptr<u8> {
    __ptr<u8> session = _pep_malloc(_TLS_SESSION_SIZE);
    _tls_set_word(session, 16, h as ulong);
    _tls_set_pointer(session, 24, context as __ptr<u8>);
    _tls_set_pointer(session, 32, _pep_malloc(_TLS_BUFFER_SIZE));
    _tls_set_pointer(session, 48, _pep_malloc(_TLS_BUFFER_SIZE));
    if (host.size > 0) {
        _tls_set_pointer(session, 96, unsafe_cast<__ptr<u8>>(io._io_win_wide(host)));
    }
    return session;
}

[Target(OS(Windows))]
_tls_session_server(session: __ptr<u8>): bool {
    return _tls_word(_tls_pointer(session, 24), 16) == 1;
}

[Target(OS(Windows))]
_tls_session_socket(session: __ptr<u8>): io.SocketHandle {
    return _tls_word(session, 16) as io.SocketHandle;
}

# Whether a security context exists (the handle is not all zero).
[Target(OS(Windows))]
_tls_session_started(session: __ptr<u8>): bool {
    if (_tls_word(session, 0) != 0) {
        return true;
    }
    return _tls_word(session, 8) != 0;
}

# Sends all `n` bytes at `data`, failing when a send makes no progress.
[Target(OS(Windows))]
_tls_send_all(session: __ptr<u8>, data: __ptr<u8>, n: ulong): io.IoResult<void> {
    return io._io_socket_send_all(_tls_session_socket(session), data, n);
}

# Receives more bytes after the ones waiting to be decrypted; how many (0 at
# the end of the stream).
[Target(OS(Windows))]
_tls_receive(session: __ptr<u8>): io.IoResult<ulong> {
    var count = _tls_word(session, 40);
    if (count >= _TLS_BUFFER_SIZE) {
        return io.IoResult<ulong>.err(_tls_error("a TLS message is larger than the receive buffer"));
    }
    var got = io._io_sys_socket_receive(
        _tls_session_socket(session), _tls_pointer(session, 32) + count, _TLS_BUFFER_SIZE - count
    );
    if (got.is_ok()) {
        _tls_set_word(session, 40, count + got.value());
    }
    return got;
}

# Keeps only the last `extra` of the waiting bytes (a SECBUFFER_EXTRA).
[Target(OS(Windows))]
_tls_keep_extra(session: __ptr<u8>, extra: ulong) {
    var buffer = _tls_pointer(session, 32);
    var count = _tls_word(session, 40);
    if (extra > 0 && extra < count) {
        _tls_copy(buffer, buffer + (count - extra), extra);
    }
    _tls_set_word(session, 40, extra);
}

# Sends and frees an output token SChannel allocated.
[Target(OS(Windows))]
_tls_send_token(session: __ptr<u8>, output: __ptr<u8>): io.IoResult<void> {
    var token = _tls_buffer_at(output, 0);
    var data = _tls_pointer(token, 8);
    if (data == __null) {
        return io.IoResult<void>.ok();
    }
    var size = _tls_u32(token, 0) as ulong;
    var sent = io.IoResult<void>.ok();
    if (size > 0) {
        sent = _tls_send_all(session, data, size);
    }
    FreeContextBuffer(data);
    _tls_set_pointer(token, 8, __null);
    return sent;
}

# One InitializeSecurityContext or AcceptSecurityContext call on the waiting
# bytes; its status. Sends any token it produces and keeps any extra bytes.
[Target(OS(Windows))]
_tls_step(session: __ptr<u8>): io.IoResult<int> {
    var context = _tls_pointer(session, 24);
    var server = _tls_session_server(session);
    var input = _tls_buffers(2);
    var output = _tls_buffers(1);
    _tls_set_buffer(input + 16, 0, _TLS_BUFFER_TOKEN, _tls_pointer(session, 32), _tls_word(session, 40));
    _tls_set_buffer(input + 16, 1, _TLS_BUFFER_EMPTY, __null, 0);
    _tls_set_buffer(output + 16, 0, _TLS_BUFFER_TOKEN, __null, 0);
    __ptr<uint> attributes = _pep_malloc(4);
    __ptr<u8> expiry = _pep_malloc(8);
    var started = _tls_session_started(session);
    __ptr<u8> existing = __null;
    if (started) {
        existing = session;
    }
    # A client's first call has no input: it produces the ClientHello.
    var consumed = started || server;
    __ptr<u8> offered = __null;
    if (consumed) {
        offered = input;
    }
    int status = 0;
    if (server) {
        var request = _TLS_SERVER_REQUEST;
        if (_tls_pointer(context, 48) != __null) {
            request = request | _TLS_SERVER_MUTUAL;
        }
        status = AcceptSecurityContext(context, existing, offered, request, 0, session, output, attributes, expiry);
    } else {
        status = InitializeSecurityContextW(
            context,
            existing,
            _tls_pointer(session, 96),
            _TLS_CLIENT_REQUEST,
            0,
            0,
            offered,
            0,
            session,
            output,
            attributes,
            expiry
        );
    }
    _pep_free(expiry);
    _pep_free(attributes);
    var sent = _tls_send_token(session, output);
    var result = io.IoResult<int>.ok(status);
    if (sent.is_err()) {
        result = io.IoResult<int>.err(sent.error());
    }
    if (consumed && status != _TLS_SEC_E_INCOMPLETE_MESSAGE) {
        var extra = _tls_buffer_at(input, 1);
        if (_tls_u32(extra, 4) == _TLS_BUFFER_EXTRA) {
            _tls_keep_extra(session, _tls_u32(extra, 0) as ulong);
        } else {
            _tls_set_word(session, 40, 0);
        }
    }
    _pep_free(output);
    _pep_free(input);
    return result;
}

# Runs handshake steps until SChannel reports the connection is set up.
[Target(OS(Windows))]
_tls_handshake(session: __ptr<u8>): io.IoResult<void> {
    # A server, and a client continuing (after SEC_I_RENEGOTIATE), start
    # from received bytes; a client's first step sends its hello.
    var need = _tls_session_server(session) && _tls_word(session, 40) == 0;
    while (true) {
        if (need) {
            var got = _tls_receive(session);
            if (got.is_err()) {
                return io.IoResult<void>.err(got.error());
            }
            if (got.value() == 0) {
                return io.IoResult<void>.err(_tls_error("TLS handshake failed: the connection closed"));
            }
        }
        var step = _tls_step(session);
        if (step.is_err()) {
            return io.IoResult<void>.err(step.error());
        }
        var status = step.value();
        if (status == _TLS_SEC_E_OK) {
            return io.IoResult<void>.ok();
        }
        if (status == _TLS_SEC_E_INCOMPLETE_MESSAGE) {
            need = true;
        } else if (status == _TLS_SEC_I_CONTINUE_NEEDED || status == _TLS_SEC_I_INCOMPLETE_CREDENTIALS) {
            need = _tls_word(session, 40) == 0;
        } else {
            return io.IoResult<void>.err(_tls_status_error("TLS handshake failed", status));
        }
    }
    return io.IoResult<void>.ok();
}

# Records the stream sizes after the handshake.
[Target(OS(Windows))]
_tls_query_sizes(session: __ptr<u8>): io.IoResult<void> {
    __ptr<u8> sizes = _pep_malloc(20);
    var status = QueryContextAttributesW(session, 4, sizes);  # SECPKG_ATTR_STREAM_SIZES
    _tls_set_u32(session, 72, _tls_u32(sizes, 0));
    _tls_set_u32(session, 76, _tls_u32(sizes, 4));
    _tls_set_u32(session, 80, _tls_u32(sizes, 8));
    _pep_free(sizes);
    if (status != _TLS_SEC_E_OK) {
        return io.IoResult<void>.err(_tls_status_error("cannot read the TLS stream sizes", status));
    }
    return io.IoResult<void>.ok();
}

# Builds `certificate`'s chain with `engine` (null for the system's) and
# checks it as a server's for `host` or, when `host` is null and `client`,
# as a client's; the policy error, 0 when it passes.
[Target(OS(Windows))]
_tls_check_chain(engine: __ptr<void>, certificate: __ptr<u8>, host: __ptr<u8>, client: bool): uint {
    __ptr<u8> parameters = _pep_malloc(24);  # CERT_CHAIN_PARA
    _tls_set_u32(parameters, 0, 24);
    __ptr<__ptr<void>> chain = _pep_malloc(8);
    chain[0] = __null;
    var additional = _tls_pointer(certificate, 32);  # CERT_CONTEXT.hCertStore
    uint error = 2148204810;                         # CERT_E_CHAINING
    if (CertGetCertificateChain(engine, certificate, __null, additional, parameters, 0, __null, chain) != 0) {
        __ptr<u8> ssl = _pep_malloc(24);  # SSL_EXTRA_CERT_CHAIN_POLICY_PARA
        _tls_set_u32(ssl, 0, 24);
        uint authentication = 2;  # AUTHTYPE_SERVER
        if (client) {
            authentication = 1;  # AUTHTYPE_CLIENT
        }
        _tls_set_u32(ssl, 4, authentication);
        _tls_set_pointer(ssl, 16, host);
        __ptr<u8> policy = _pep_malloc(16);  # CERT_CHAIN_POLICY_PARA
        _tls_set_u32(policy, 0, 16);
        _tls_set_pointer(policy, 8, ssl);
        __ptr<u8> status = _pep_malloc(24);  # CERT_CHAIN_POLICY_STATUS
        _tls_set_u32(status, 0, 24);
        if (CertVerifyCertificateChainPolicy(4, chain[0], policy, status) != 0) {  # CERT_CHAIN_POLICY_SSL
            error = _tls_u32(status, 4);
        }
        _pep_free(status);
        _pep_free(policy);
        _pep_free(ssl);
        CertFreeCertificateChain(chain[0]);
    }
    _pep_free(chain);
    _pep_free(parameters);
    return error;
}

# Checks the server's certificate for the session's host: against the
# system's roots, then against only the added ones.
[Target(OS(Windows))]
_tls_verify(session: __ptr<u8>): io.IoResult<void> {
    __ptr<__ptr<u8>> remote = _pep_malloc(8);
    remote[0] = __null;
    var status = QueryContextAttributesW(session, 83, remote);  # SECPKG_ATTR_REMOTE_CERT_CONTEXT
    var certificate = remote[0];
    _pep_free(remote);
    if (status != _TLS_SEC_E_OK || certificate == __null) {
        return io.IoResult<void>.err(
            _tls_status_error("certificate verify failed: the server sent no certificate", status)
        );
    }
    var host = _tls_pointer(session, 96);
    var error = _tls_check_chain(__null, certificate, host, false);
    var roots = _tls_pointer(_tls_pointer(session, 24), 24);
    if (error != 0 && roots != __null) {
        # CERT_CHAIN_ENGINE_CONFIG (Windows 8 and later): 88 bytes,
        # hExclusiveRoot at 64.
        __ptr<u8> config = _pep_malloc(88);
        _tls_set_u32(config, 0, 88);
        _tls_set_pointer(config, 64, roots);
        __ptr<__ptr<void>> engine = _pep_malloc(8);
        engine[0] = __null;
        if (CertCreateCertificateChainEngine(config, engine) != 0) {
            var added_error = _tls_check_chain(engine[0], certificate, host, false);
            # A name mismatch found with the added roots says more than the
            # system's "untrusted root".
            if (added_error == 0 || error == 2148204809) {
                error = added_error;
            }
            CertFreeCertificateChainEngine(engine[0]);
        }
        _pep_free(engine);
        _pep_free(config);
    }
    CertFreeCertificateContext(certificate);
    if (error != 0) {
        return io.IoResult<void>.err(_tls_error($"certificate verify failed: {_tls_certificate_reason(error)}"));
    }
    return io.IoResult<void>.ok();
}

# Runs the client handshake on socket `h`, checking that the certificate is
# for `host` (a name, or an IP address).
[Target(OS(Windows))]
_tls_sys_connect(context: __ptr<void>, h: io.SocketHandle, host: String): io.IoResult<__ptr<void>> {
    var session = _tls_session_new(context, h, host);
    # SNI carries names only: an IP address goes to the certificate check.
    var target = _tls_pointer(session, 96);
    var by_address = io.IpAddress.parse(host).is_ok();
    if (by_address) {
        _tls_set_pointer(session, 96, __null);
    }
    var done = _tls_handshake(session);
    if (by_address) {
        _tls_set_pointer(session, 96, target);
    }
    if (done.is_ok()) {
        done = _tls_verify(session);
    }
    if (done.is_ok()) {
        done = _tls_query_sizes(session);
    }
    if (done.is_err()) {
        _tls_sys_session_free(session);
        return io.IoResult<__ptr<void>>.err(done.error());
    }
    return io.IoResult<__ptr<void>>.ok(session);
}

# Checks the client's certificate against only the context's roots for
# client certificates.
[Target(OS(Windows))]
_tls_verify_client(session: __ptr<u8>): io.IoResult<void> {
    var roots = _tls_pointer(_tls_pointer(session, 24), 48);
    __ptr<__ptr<u8>> remote = _pep_malloc(8);
    remote[0] = __null;
    var status = QueryContextAttributesW(session, 83, remote);  # SECPKG_ATTR_REMOTE_CERT_CONTEXT
    var certificate = remote[0];
    _pep_free(remote);
    if (status != _TLS_SEC_E_OK || certificate == __null) {
        return io.IoResult<void>.err(_tls_error("TLS handshake failed: the client sent no certificate"));
    }
    uint error = 2148204810;  # CERT_E_CHAINING
    # CERT_CHAIN_ENGINE_CONFIG (Windows 8 and later): 88 bytes,
    # hExclusiveRoot at 64.
    __ptr<u8> config = _pep_malloc(88);
    _tls_set_u32(config, 0, 88);
    _tls_set_pointer(config, 64, roots);
    __ptr<__ptr<void>> engine = _pep_malloc(8);
    engine[0] = __null;
    if (CertCreateCertificateChainEngine(config, engine) != 0) {
        error = _tls_check_chain(engine[0], certificate, __null, true);
        CertFreeCertificateChainEngine(engine[0]);
    }
    _pep_free(engine);
    _pep_free(config);
    CertFreeCertificateContext(certificate);
    if (error != 0) {
        return io.IoResult<void>.err(_tls_error($"certificate verify failed: {_tls_certificate_reason(error)}"));
    }
    return io.IoResult<void>.ok();
}

# Runs the server handshake on socket `h`, checking the client's certificate
# when the context asks for one.
[Target(OS(Windows))]
_tls_sys_accept(context: __ptr<void>, h: io.SocketHandle): io.IoResult<__ptr<void>> {
    var session = _tls_session_new(context, h, "");
    var done = _tls_handshake(session);
    if (done.is_ok() && _tls_pointer(context as __ptr<u8>, 48) != __null) {
        done = _tls_verify_client(session);
    }
    if (done.is_ok()) {
        done = _tls_query_sizes(session);
    }
    if (done.is_err()) {
        _tls_sys_session_free(session);
        return io.IoResult<__ptr<void>>.err(done.error());
    }
    return io.IoResult<__ptr<void>>.ok(session);
}

# Copies up to `n` decrypted bytes waiting in the session to `destination`.
[Target(OS(Windows))]
_tls_take_plain(session: __ptr<u8>, destination: __ptr<u8>, n: ulong): ulong {
    var start = _tls_word(session, 56);
    var end = _tls_word(session, 64);
    var take = end - start;
    if (take > n) {
        take = n;
    }
    _tls_copy(destination, _tls_pointer(session, 48) + start, take);
    _tls_set_word(session, 56, start + take);
    return take;
}

# Decrypts the waiting bytes; the status. Decrypted bytes go to the
# plaintext buffer and bytes after the record stay waiting.
[Target(OS(Windows))]
_tls_decrypt(session: __ptr<u8>): int {
    var desc = _tls_buffers(4);
    _tls_set_buffer(desc + 16, 0, _TLS_BUFFER_DATA, _tls_pointer(session, 32), _tls_word(session, 40));
    var status = DecryptMessage(session, desc, 0, __null);
    if (status == _TLS_SEC_E_OK || status == _TLS_SEC_I_RENEGOTIATE || status == _TLS_SEC_I_CONTEXT_EXPIRED) {
        ulong extra = 0;
        ulong i = 1;
        while (i < 4) {
            var buffer = _tls_buffer_at(desc, i);
            var kind = _tls_u32(buffer, 4);
            if (kind == _TLS_BUFFER_DATA) {
                var size = _tls_u32(buffer, 0) as ulong;
                _tls_copy(_tls_pointer(session, 48), _tls_pointer(buffer, 8), size);
                _tls_set_word(session, 56, 0);
                _tls_set_word(session, 64, size);
            } else if (kind == _TLS_BUFFER_EXTRA) {
                extra = _tls_u32(buffer, 0) as ulong;
            }
            i = i + 1;
        }
        _tls_keep_extra(session, extra);
    }
    _pep_free(desc);
    return status;
}

# Reads up to `n` decrypted bytes into `destination`; 0 at the end of the
# stream.
[Target(OS(Windows))]
_tls_sys_read(session: __ptr<void>, destination: __ptr<u8>, n: ulong): io.IoResult<ulong> {
    __ptr<u8> block = session;
    while (true) {
        if (_tls_word(block, 64) > _tls_word(block, 56)) {
            return io.IoResult<ulong>.ok(_tls_take_plain(block, destination, n));
        }
        if (_tls_word(block, 88) != 0) {
            return io.IoResult<ulong>.ok(0);
        }
        var status = _TLS_SEC_E_INCOMPLETE_MESSAGE;
        if (_tls_word(block, 40) > 0) {
            status = _tls_decrypt(block);
        }
        if (status == _TLS_SEC_I_CONTEXT_EXPIRED) {
            # close_notify
            _tls_set_word(block, 88, 1);
        } else if (status == _TLS_SEC_I_RENEGOTIATE) {
            # TLS 1.3 post-handshake messages (a session ticket, a key
            # update): the waiting bytes go back through the handshake.
            var again = _tls_handshake(block);
            if (again.is_err()) {
                return io.IoResult<ulong>.err(again.error());
            }
        } else if (status == _TLS_SEC_E_INCOMPLETE_MESSAGE) {
            var got = _tls_receive(block);
            if (got.is_err()) {
                return io.IoResult<ulong>.err(got.error());
            }
            if (got.value() == 0) {
                # The peer closed the socket without close_notify: the end
                # of the stream, as with OpenSSL's SSL_OP_IGNORE_UNEXPECTED_EOF.
                _tls_set_word(block, 88, 1);
            }
        } else if (status != _TLS_SEC_E_OK) {
            return io.IoResult<ulong>.err(_tls_status_error("TLS read failed", status));
        }
    }
    return io.IoResult<ulong>.ok(0);
}

# Encrypts and sends up to `n` bytes from `source`: at most one TLS record.
[Target(OS(Windows))]
_tls_sys_write(session: __ptr<void>, source: __ptr<u8>, n: ulong): io.IoResult<ulong> {
    if (n == 0) {
        return io.IoResult<ulong>.ok(0);
    }
    __ptr<u8> block = session;
    var header = _tls_u32(block, 72) as ulong;
    var trailer = _tls_u32(block, 76) as ulong;
    var chunk = _tls_u32(block, 80) as ulong;
    if (chunk > n) {
        chunk = n;
    }
    __ptr<u8> record = _pep_malloc(header + chunk + trailer);
    _tls_copy(record + header, source, chunk);
    var desc = _tls_buffers(4);
    _tls_set_buffer(desc + 16, 0, _TLS_BUFFER_HEADER, record, header);
    _tls_set_buffer(desc + 16, 1, _TLS_BUFFER_DATA, record + header, chunk);
    _tls_set_buffer(desc + 16, 2, _TLS_BUFFER_TRAILER, record + header + chunk, trailer);
    _tls_set_buffer(desc + 16, 3, _TLS_BUFFER_EMPTY, __null, 0);
    var status = EncryptMessage(block, 0, desc, 0);
    var result = io.IoResult<ulong>.ok(chunk);
    if (status != _TLS_SEC_E_OK) {
        result = io.IoResult<ulong>.err(_tls_status_error("TLS write failed", status));
    } else {
        var size = _tls_u32(_tls_buffer_at(desc, 0), 0) as ulong;
        size = size + _tls_u32(_tls_buffer_at(desc, 1), 0) as ulong;
        size = size + _tls_u32(_tls_buffer_at(desc, 2), 0) as ulong;
        var sent = _tls_send_all(block, record, size);
        if (sent.is_err()) {
            result = io.IoResult<ulong>.err(sent.error());
        }
    }
    _pep_free(desc);
    _pep_free(record);
    return result;
}

# Sends close_notify.
[Target(OS(Windows))]
_tls_sys_shutdown(session: __ptr<void>): io.IoResult<void> {
    __ptr<u8> block = session;
    __ptr<uint> kind = _pep_malloc(4);
    kind[0] = 1;  # SCHANNEL_SHUTDOWN
    var desc = _tls_buffers(1);
    _tls_set_buffer(desc + 16, 0, _TLS_BUFFER_TOKEN, unsafe_cast<__ptr<u8>>(kind), 4);
    var status = ApplyControlToken(block, desc);
    _pep_free(desc);
    _pep_free(kind);
    if (status != _TLS_SEC_E_OK) {
        return io.IoResult<void>.err(_tls_status_error("TLS shutdown failed", status));
    }
    # The next call produces the close_notify alert.
    var output = _tls_buffers(1);
    _tls_set_buffer(output + 16, 0, _TLS_BUFFER_TOKEN, __null, 0);
    __ptr<uint> attributes = _pep_malloc(4);
    __ptr<u8> expiry = _pep_malloc(8);
    var context = _tls_pointer(block, 24);
    if (_tls_session_server(block)) {
        status = AcceptSecurityContext(
            context, block, __null, _TLS_SERVER_REQUEST, 0, block, output, attributes, expiry
        );
    } else {
        status = InitializeSecurityContextW(
            context,
            block,
            _tls_pointer(block, 96),
            _TLS_CLIENT_REQUEST,
            0,
            0,
            __null,
            0,
            block,
            output,
            attributes,
            expiry
        );
    }
    _pep_free(expiry);
    _pep_free(attributes);
    var sent = _tls_send_token(block, output);
    _pep_free(output);
    if (status != _TLS_SEC_E_OK && status != _TLS_SEC_I_CONTEXT_EXPIRED) {
        return io.IoResult<void>.err(_tls_status_error("TLS shutdown failed", status));
    }
    return sent;
}

# Deletes the security context and frees the block.
[Target(OS(Windows))]
_tls_sys_session_free(session: __ptr<void>) {
    __ptr<u8> block = session;
    if (_tls_session_started(block)) {
        DeleteSecurityContext(block);
    }
    _pep_free(_tls_pointer(block, 32));
    _pep_free(_tls_pointer(block, 48));
    var host = _tls_pointer(block, 96);
    if (host != __null) {
        _pep_free(host);
    }
    _pep_free(block);
}
