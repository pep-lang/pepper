# Code for other platforms: the parts of a document a `[Target(...)]`
# attribute leaves out on a target, which the editor shows dimmed, as clang
# does for an inactive `#if`, and the OS to analyze a document for. It
# mirrors what linking and sema drop, no more: constructors, destructors
# and fields are always compiled. Attributed blocks are dropped wherever
# statements are, `for`, `with` and `match` bodies included.

import [Attribute, Block, FunctionDecl, Module, Span] from compiler.ast;
import compiler.link;
import lsp;
import "scope";

## The OSes a document may be analyzed for, besides the build target's.
export const OSES = "windows linux macos";

## Every span of `text` (parsed as `module`) its `[Target(...)]` attributes
## leave out on `target`, outermost only, in source order, without the
## whitespace after each.
##
## @param text the document's text
## @param module its syntax tree
## @param target the target
## @returns the spans
export inactive_regions(text: String, module: Module, target: link.Target): Span[] {
    var out = Array<Span>();
    for (var import_ in module.imports) {
        if (_inactive(target, import_.attributes)) {
            out.append(import_.span);
        }
    }
    for (var export_ in module.exports) {
        if (_inactive(target, export_.attributes)) {
            out.append(export_.span);
        }
    }
    for (var declaration in module.declarations) {
        if (_inactive(target, declaration.attributes())) {
            out.append(_with_attributes(declaration.attributes(), declaration.span()));
            continue;
        }
        match (declaration) {
            Function(f) => {
                _function(target, f, out);
            }
            Struct(s) => {
                if (s.enumeration is Value(body)) {
                    for (var case in body.cases) {
                        if (_inactive(target, case.attributes)) {
                            out.append(_with_attributes(case.attributes, case.span));
                        }
                    }
                }
                for (var m in s.methods) {
                    _function(target, m, out);
                }
                # Never dropped, whatever their attributes: only the blocks
                # inside.
                for (var c in s.constructors) {
                    if (c.body is Value(body)) {
                        _statements(target, body, out);
                    }
                }
                if (s.destructor is Value(body)) {
                    _statements(target, body, out);
                }
            }
            Trait(t) => {
                for (var m in t.methods) {
                    _function(target, m, out);
                }
            }
            Extend(e) => {
                for (var m in e.methods) {
                    _function(target, m, out);
                }
            }
            Static(s) => {
                _statements(target, s.block, out);
            }
            else => {}
        }
    }
    out.sort((a: Span, b: Span) => a.start < b.start ? -1 : (a.start > b.start ? 1 : 0));
    var trimmed = Array<Span>();
    for (var span in out) {
        var end = span.end < text.size ? span.end : text.size;
        while (end > span.start and _is_space(text.byte_at(end - 1))) {
            end -= 1;
        }
        trimmed.append(Span(span.start, end));
    }
    return trimmed;
}

## A dimmed hint over each region of the document `target` leaves out, as
## a diagnostic with the `Unnecessary` tag, which editors show faded.
##
## @param document the document
## @param module its syntax tree
## @param target the build target
## @returns the hints
export inactive_hints(document: lsp.TextDocument, module: Module, target: link.Target): lsp.Diagnostic[] {
    var out = Array<lsp.Diagnostic>();
    var shown = _os_name(target.os) + " " + target.arch;
    for (var span in inactive_regions(document.text, module, target)) {
        var hint = lsp.Diagnostic(
            document.range_of(span.start, span.end),
            $"inactive: not compiled for this target ({shown})",
            lsp.SEVERITY_HINT
        );
        hint.source = Optional<String>.Value("pepper");
        hint.tags = Optional<Array<int>>.Value([lsp.TAG_UNNECESSARY]);
        out.append(hint);
    }
    return out;
}

## The OS to analyze `text` (parsed as `module`) for: the build target's,
## unless its build leaves out most of the document and none of what it
## keeps is another OS's to drop, as for a file of Linux-only code on
## Windows; then the OS whose build leaves out the least of it. A mostly
## portable file stays on the build target, so the errors its build would
## report still show.
##
## @param text the document's text
## @param module its syntax tree
## @param host the build target
## @returns the OS
export analysis_os(text: String, module: Module, host: link.Target): String {
    var at_host = inactive_regions(text, module, host);
    if (at_host.count == 0) {
        return host.os;
    }
    var others = Array<String>();
    var dropped = Array<Array<Span>>();
    for (var os in OSES.split(" ")) {
        if (os != host.os) {
            others.append(os);
            dropped.append(inactive_regions(text, module, target_for(host, os)));
        }
    }
    # Code the build target keeps and another OS drops is the build
    # target's own: analyze for it.
    for (var regions in dropped) {
        for (var span in regions) {
            if (!_inside_any(span, at_host)) {
                return host.os;
            }
        }
    }
    var at_host_code = _code_in_regions(text, at_host);
    if (at_host_code * 2 <= _code_in(text)) {
        return host.os;
    }
    var best = host.os;
    var least = at_host_code;
    ulong i = 0;
    while (i < others.count) {
        var code = _code_in_regions(text, dropped[i]);
        if (code < least) {
            least = code;
            best = others[i];
        }
        i += 1;
    }
    return best;
}

## `host` with its OS replaced by `os`: its architecture and build options
## kept.
##
## @param host the build target
## @param os the OS
## @returns the target
export target_for(host: link.Target, os: String): link.Target {
    var target = link.Target();
    target.os = os;
    target.arch = host.arch;
    for (var (name, value) in host.build_options) {
        target.build_options[name] = value;
    }
    return target;
}

# Whether `attributes` leave their target out. A malformed `Target(...)`
# is reported by sema, not dimmed.
_inactive(target: link.Target, attributes: Attribute[]): bool {
    var kept = target.keep(attributes);
    return kept.is_ok() and !kept.value();
}

# From the first of `attributes` (or `span`'s start) to `span`'s end.
_with_attributes(attributes: Attribute[], span: Span): Span {
    var start = span.start;
    for (var attribute in attributes) {
        if (attribute.span.start < start) {
            start = attribute.span.start;
        }
    }
    return Span(start, span.end);
}

# A function, method or constructor: all of it, or its inactive blocks.
_function(target: link.Target, f: FunctionDecl, out: Span[]) {
    if (_inactive(target, f.attributes)) {
        # A method's span starts after its name.
        var start = f.span.start < f.name_span.start ? f.span.start : f.name_span.start;
        out.append(_with_attributes(f.attributes, Span(start, f.span.end)));
        return;
    }
    if (f.body is Value(body)) {
        _statements(target, body, out);
    }
}

# The inactive blocks among `block`'s statements and the bodies nested in
# them; a block's span includes its attributes.
_statements(target: link.Target, block: Block, out: Span[]) {
    var stack = [block];
    while (stack.count > 0) {
        var b = stack.pop();
        for (var statement in b.statements) {
            for (var inner in statement_blocks(statement)) {
                if (_inactive(target, inner.attributes)) {
                    out.append(inner.span);
                } else {
                    stack.append(inner);
                }
            }
        }
    }
}

# Whether `span` lies inside one of `regions`.
_inside_any(span: Span, regions: Span[]): bool {
    for (var region in regions) {
        if (region.start <= span.start and span.end <= region.end) {
            return true;
        }
    }
    return false;
}

# How much code `regions` of `text` hold.
_code_in_regions(text: String, regions: Span[]): ulong {
    ulong total = 0;
    for (var span in regions) {
        total += _code_in(text.substr_bytes(span.start, span.end - span.start));
    }
    return total;
}

# How much code `part` holds, measured alike everywhere: the bytes of its
# trimmed lines, comments and blank lines aside.
_code_in(part: String): ulong {
    ulong total = 0;
    for (var line in part.split("\n")) {
        var trimmed = line.trim();
        if (!trimmed.is_empty and !trimmed.starts_with("#")) {
            total += trimmed.size;
        }
    }
    return total;
}

# The OS as `Target(OS(...))` spells it.
_os_name(os: String): String {
    if (os == "windows") {
        return "Windows";
    }
    if (os == "linux") {
        return "Linux";
    }
    if (os == "macos") {
        return "macOS";
    }
    return os;
}

_is_space(b: u8): bool {
    return b == ' ' or b == '\t' or b == '\n' or b == '\r';
}
