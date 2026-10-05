<!-- Generated from runtime/uri.pep by `pep-doc reference`. Do not edit. -->

# URI

URI references (RFC 3986): parse any URI, such as `https://example.com/a?b#c`,
`mailto:someone@example.com` or `/items?page=2`, into its parts.

Source: `runtime/uri.pep`

## Uri

```pepper
struct Uri
```

A URI reference split into its RFC 3986 components: scheme, authority
(user information, host and port), path, query and fragment.

`Uri.parse` accepts any scheme, and a reference with no scheme (a
relative reference, such as `/items?page=2`, which is what an HTTP
server sees as a request's target). The components keep their
percent-escapes as written; `Uri.decode` turns an escaped component into
text. The scheme is lowercased, since schemes are case-insensitive;
nothing else is changed. `to_string()` puts the parts back together.

A component that can be absent is optional, so an empty one (`http://h/?`
has an empty query) differs from a missing one (`http://h/` has none).

**Example**
```pepper
var uri = Uri.parse("HTTPS://user@example.com:8443/a%20b?x=1#top").value();
assert(uri.scheme == "https", "the scheme is lowercased");
assert(uri.user_info.value() == "user", "user information");
assert(uri.host.value() == "example.com", "host");
assert(uri.port.value() == 8443, "port");
assert(uri.path == "/a%20b", "the path keeps its escapes");
assert(Uri.decode(uri.path).value() == "/a b", "decoded");
assert(uri.query.value() == "x=1" && uri.fragment.value() == "top", "query and fragment");
```

### Fields

#### scheme

```pepper
var scheme: String
```

The scheme, lowercased, such as `https`; empty for a relative reference.

#### user_info

```pepper
var user_info: String?
```

The user information before `@` in the authority, if any.

#### host

```pepper
var host: String?
```

The host, without the brackets of an IPv6 address; Empty when the URI
has no authority (no `//`), and empty for one such as `file:///tmp`.
An IPv6 scope keeps its escaped `%` (RFC 6874): the host of
`http://[fe80::1%25eth0]/` is `fe80::1%25eth0`, which `Uri.decode`
turns into the `fe80::1%eth0` that `io.IpAddress.parse` reads.

#### port

```pepper
var port: u16?
```

The port after the host, if the authority gives one.

#### path

```pepper
var path: String
```

The path, possibly empty, with its percent-escapes.

#### query

```pepper
var query: String?
```

The query after `?`, without the `?`, if any.

#### fragment

```pepper
var fragment: String?
```

The fragment after `#`, without the `#`, if any.

### Constructor

#### Uri()

```pepper
construct()
```

Creates an empty relative reference: no scheme, no authority, and an
empty path.

### Static methods

#### parse

```pepper
static parse(text: String): Result<Uri>
```

Parses `text` as a URI reference: an absolute URI with any scheme,
or a relative reference.

Characters outside printable ASCII (spaces, controls, and every
non-ASCII byte) must be percent-encoded, and each `%` must be
followed by two hexadecimal digits.

**Parameters**
- `text` — the URI reference

**Returns**
- the parsed URI, or an error saying what is wrong: an invalid scheme, a character that must be encoded, a bad escape, an IPv6 host with no `]`, or a port that is not a number from 0 to 65535

**Example**
```pepper
var mail = Uri.parse("mailto:someone@example.com").value();
assert(mail.scheme == "mailto" && mail.host.is_empty(), "no authority");
assert(mail.path == "someone@example.com", "the path holds the address");
assert(Uri.parse("a b").is_err(), "a space must be encoded");
```

#### decode

```pepper
static decode(text: String): Result<String>
```

Returns `text` with each percent-escape (`%20`) replaced by the byte
it stands for, decoded as UTF-8. A `+` is kept as it is; a query that
uses `+` for a space needs that replaced first.

**Parameters**
- `text` — a component with percent-escapes, such as `path`

**Returns**
- the decoded text, where each byte sequence that is not valid UTF-8 becomes U+FFFD, the replacement character, or an error when a `%` is not followed by two hexadecimal digits

**Example**
```pepper
assert(Uri.decode("caf%C3%A9%21").value() == "café!", "decoded");
assert(Uri.decode("100%").is_err(), "a lone '%'");
```

### Methods

#### is_absolute

```pepper
is_absolute(): bool
```

Returns whether this URI has a scheme (an absolute URI rather than a
relative reference).

**Returns**
- true when `scheme` is not empty

#### authority

```pepper
authority(): String?
```

Returns the authority as it appears after `//`: user information,
host (in brackets when it is an IPv6 address) and port.

**Returns**
- the authority, such as `user@example.com:8443`, or Empty when `host` is Empty

#### path_and_query

```pepper
path_and_query(): String
```

Returns the path and query, as an HTTP request line names its target:
the path (`/` when it is empty), then `?` and the query if there is
one. The fragment is left out.

**Returns**
- the path and query, such as `/items?page=2`

#### resolve

```pepper
resolve(reference: Uri): Uri
```

Resolves `reference` against this URI, its base, as RFC 3986
(section 5.2) describes and as a browser resolves a link on a page:
an absolute `reference` stands as it is, `//host/path` keeps only the
base's scheme, `/path` keeps its authority too, and a relative path
replaces the base's last segment. `.` and `..` segments are removed.
The fragment is always the reference's.

**Parameters**
- `reference` — the reference to resolve, such as an HTTP `Location`

**Returns**
- the resolved URI

**Example**
```pepper
var base = Uri.parse("https://example.com/docs/guide/intro?x=1").value();
assert(base.resolve(Uri.parse("next").value()).to_string() == "https://example.com/docs/guide/next", "a sibling");
assert(base.resolve(Uri.parse("../api").value()).to_string() == "https://example.com/docs/api", "up one");
assert(base.resolve(Uri.parse("/").value()).to_string() == "https://example.com/", "the root");
assert(base.resolve(Uri.parse("?y=2").value()).to_string() == "https://example.com/docs/guide/intro?y=2", "a new query");
```

#### to_string

```pepper
to_string(): String
```

Returns the URI as text, putting its components back together. For a
parsed URI this is the text it was parsed from, except that the
scheme is lowercased.

**Returns**
- the URI reference as a String
