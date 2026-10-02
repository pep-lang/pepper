## HTTP messages: `Headers`, `Request` and `Response`, the values a
## `Client` sends and receives and a `Server` handler takes and returns.

import text;

## HTTP header fields, by name. Names ignore ASCII case: they are stored
## lowercased, so `Content-Type` and `content-type` are the same field. A
## name may hold several values, kept in the order added. Different names
## have no defined order, as HTTP allows.
##
## @example
##     var headers = http.Headers();
##     headers.add("Accept", "text/html");
##     headers["accept"] = "application/json";   # replaces it
##     assert(headers["ACCEPT"] == "application/json", "one value");
export struct Headers {
    # Each field's values, under its lowercased name.
    var _fields: HashMap<String, String[]>;

    ## Creates an empty set of fields.
    construct() {
        this._fields = HashMap<String, String[]>();
    }

    ## The number of field names.
    var count: ulong {
        get {
            return this._fields.count as ulong;
        }
    }

    ## Returns the field names, lowercased, in no defined order.
    ##
    ## @returns a new array with one entry per name
    names(): String[] {
        var result = Array<String>();
        for (var (name, values) in this._fields) {
            result.append(name);
        }
        return result;
    }

    ## Returns every value of the field named `name`, in the order added.
    ##
    ## @param name the field name, in any case
    ## @returns a new array of the values; empty when no field has that name
    values(name: String): String[] {
        # One lookup: `get` gives null for a missing field.
        var found = this._fields.get(name.lower());
        if (found === __null) {
            return Array<String>();
        }
        return found.clone();
    }

    ## Adds a value to the field named `name`, keeping any it has.
    ##
    ## @param name the field name, in any case
    ## @param value the field value
    add(name: String, value: String) {
        var key = name.lower();
        var found = this._fields.get(key);
        if (found === __null) {
            found = Array<String>();
            this._fields[key] = found;
        }
        found.append(value);
    }

    ## Replaces every value of the field named `name` with `value`.
    ##
    ## @param name the field name, in any case
    ## @param value the field value
    set(name: String, value: String) {
        this._fields[name.lower()] = [value];
    }

    ## Returns the first value of the field named `name`.
    ##
    ## @param name the field name, in any case
    ## @returns the value, or none when no field has that name
    get(name: String): String? {
        var found = this._fields.get(name.lower());
        if (found === __null) {
            return Optional<String>.Empty;
        }
        return Optional<String>.Value(found[0]);
    }

    ## Reports whether a field is named `name`.
    ##
    ## @param name the field name, in any case
    ## @returns true if a field has that name
    has(name: String): bool {
        return this._fields.contains(name.lower());
    }

    ## Removes the field named `name` and all its values.
    ##
    ## @param name the field name, in any case
    remove(name: String) {
        this._fields.remove(name.lower());
    }

    ## Reads `headers[name]`: the first value of the field named `name`, or
    ## an empty string when there is none. Use `get` to tell an empty value
    ## from a missing field.
    ##
    ## @param name the field name, in any case
    ## @returns the first value, or `""`
    [](name: String): String {
        var found = this._fields.get(name.lower());
        if (found === __null) {
            return "";
        }
        return found[0];
    }

    ## Writes `headers[name] = value`: replaces every value of the field, as
    ## `set` does.
    ##
    ## @param name the field name, in any case
    ## @param value the field value
    ## @returns `value`, the value of the assignment expression
    [](name: String, value: String): String {
        this.set(name, value);
        return value;
    }
}

## An HTTP request.
##
## A `Client` sends one: build it with a method and an absolute URL, then
## add headers and a body. A `Server` handler receives one, with `url` set to
## the target from the request line (`/path?query`) and the body read in
## full.
##
## @example
##     var request = http.Request("POST", "http://localhost:8080/items").set_text("name=pepper");
##     request.headers["Content-Type"] = "application/x-www-form-urlencoded";
export struct Request {
    ## The method, such as `GET` or `POST`.
    var method: String;
    ## For a client, the absolute URL (`https://host/path?query`); for a
    ## server handler, the request target (`/path?query`).
    var url: String;
    ## The header fields. A client adds `Host`, `Content-Length` and
    ## `Connection` itself.
    var headers: Headers;
    # The body's bytes; empty for none.
    var _body: u8[];

    ## Creates a request with no headers and no body.
    ##
    ## @param method the method, such as `GET`
    ## @param url the absolute URL to send it to
    construct(method: String = "GET", url: String = "/") {
        this.method = method;
        this.url = url;
        this.headers = Headers();
        this._body = Array<u8>();
    }

    ## Sets the body to the UTF-8 bytes of `text`.
    ##
    ## @param text the body
    ## @returns this request
    set_text(text: String): Request {
        this._body = text.bytes();
        return this;
    }

    ## Sets the body to `data`, which may be any bytes (see `body`).
    ##
    ## @param data the body's bytes
    ## @returns this request
    set_body(data: u8[]): Request {
        this._body = data;
        return this;
    }

    ## Parses `url` as a URI reference: an absolute URL for a request a
    ## client sends, or the target (`/items?page=2`) for one a server
    ## received.
    ##
    ## @returns the parsed URL, or an error when `url` is not a valid URI
    ##   reference (see `Uri.parse`)
    uri(): Result<Uri> {
        return Uri.parse(this.url);
    }

    ## Returns the path of `url`, with its percent-escapes: `/` when the path
    ## is empty.
    ##
    ## @returns the path, such as `/items`, or an empty string when `url` is
    ##   not a valid URI reference
    path(): String {
        var parsed = this.uri();
        if (parsed.is_err()) {
            return "";
        }
        var path = parsed.value().path;
        if (path.size == 0) {
            return "/";
        }
        return path;
    }

    ## Returns the query of `url`: the text after `?`, with its
    ## percent-escapes (see `Uri.decode`).
    ##
    ## @returns the query without the `?`, or an empty string for none or
    ##   when `url` is not a valid URI reference
    query(): String {
        var parsed = this.uri();
        if (parsed.is_err()) {
            return "";
        }
        return parsed.value().query.value_or("");
    }

    ## Returns the body's bytes, as they were sent or received: use it for a
    ## binary body. The array is the body itself, not a copy.
    ##
    ## @returns the body; empty for none
    body(): u8[] {
        return this._body;
    }

    ## Returns the body as text, decoded as UTF-8. For a binary body, call
    ## `body()` instead: here each byte that is not valid UTF-8 becomes
    ## U+FFFD, the replacement character.
    ##
    ## @returns the body's bytes decoded as a String
    text(): String {
        return _http_body_text(this._body);
    }
}

## An HTTP response.
##
## A `Client` returns one with the body read in full. A `Server` handler
## returns one: build it with a status, then add headers and a body. The
## server adds `Content-Length` itself.
##
## @example
##     handle(request: http.Request): http.Response {
##         var response = http.Response(200).set_text("hello");
##         response.headers["Content-Type"] = "text/plain";
##         return response;
##     }
export struct Response {
    ## The status code, such as 200 or 404.
    var status: int;
    ## The reason phrase, such as `OK`; the server sends the standard one
    ## for the status when this is empty.
    var reason: String;
    ## The header fields.
    var headers: Headers;
    # The body's bytes; empty for none.
    var _body: u8[];

    ## Creates a response with no headers and no body.
    ##
    ## @param status the status code
    construct(status: int = 200) {
        this.status = status;
        this.reason = "";
        this.headers = Headers();
        this._body = Array<u8>();
    }

    ## Sets the body to the UTF-8 bytes of `text`.
    ##
    ## @param text the body
    ## @returns this response
    set_text(text: String): Response {
        this._body = text.bytes();
        return this;
    }

    ## Sets the body to `data`, which may be any bytes (see `body`).
    ##
    ## @param data the body's bytes
    ## @returns this response
    set_body(data: u8[]): Response {
        this._body = data;
        return this;
    }

    ## Returns the body's bytes, as they were sent or received: use it for a
    ## binary body. The array is the body itself, not a copy.
    ##
    ## @returns the body; empty for none
    body(): u8[] {
        return this._body;
    }

    ## Returns the body as text, decoded as UTF-8. For a binary body, call
    ## `body()` instead: here each byte that is not valid UTF-8 becomes
    ## U+FFFD, the replacement character.
    ##
    ## @returns the body's bytes decoded as a String
    text(): String {
        return _http_body_text(this._body);
    }

    ## Reports whether the status is 2xx.
    ##
    ## @returns true for a status from 200 to 299
    is_success(): bool {
        return this.status >= 200 && this.status < 300;
    }
}

# `body` decoded as UTF-8, invalid bytes becoming U+FFFD. Outside the
# structs, whose `text()` methods would take the name `text`.
_http_body_text(body: u8[]): String {
    return text.Utf8.decode_lossy(body);
}
