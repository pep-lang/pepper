# The regex compiler: a syntax tree from `syntax.pep` to a program of
# instructions for the Pike VM in `match.pep`, in the style of Thompson's
# construction.

import "syntax";

# Consume a CHAR: `a` is the code point.
export const _REGEX_OP_CHAR = 0;
# Consume any code point but a newline.
export const _REGEX_OP_ANY = 1;
# Consume any code point.
export const _REGEX_OP_ANY_NEWLINE = 2;
# Consume a code point in class `a`.
export const _REGEX_OP_CLASS = 3;
# Continue at both `a` (preferred) and `b`.
export const _REGEX_OP_SPLIT = 4;
# Continue at `a`.
export const _REGEX_OP_JUMP = 5;
# Record the position in capture slot `a`.
export const _REGEX_OP_SAVE = 6;
# Continue only where the `_REGEX_AT_` assertion `a` holds.
export const _REGEX_OP_ASSERT = 7;
# The pattern matched.
export const _REGEX_OP_MATCH = 8;

# Patterns whose program would be larger fail to compile.
export const _REGEX_MAX_INSTRUCTIONS: ulong = 100000;

# A compiled pattern: its instructions, character classes and group names.
# Immutable once compiled.
export struct _RegexProgram {
    var ops: int[];
    var a: ulong[];
    var b: ulong[];
    # The ranges of every class, packed as in `_RegexNode.ranges`; class `k`
    # owns `ranges[class_starts[k]]` up to `ranges[class_starts[k + 1]]`.
    var ranges: ulong[];
    var class_starts: ulong[];
    # The number of capture groups, not counting the whole match.
    var group_count: ulong;
    # The name of each group by index; "" when unnamed.
    var names: String[];
    # Whether every match must start at the start of the text (`\A...`).
    var anchored: bool;

    construct() {
        ops = Array<int>();
        a = Array<ulong>();
        b = Array<ulong>();
        ranges = Array<ulong>();
        class_starts = Array<ulong>();
        class_starts.append(0);
        group_count = 0;
        names = Array<String>();
        anchored = false;
    }

    # The number of capture slots: a start and an end for each group and
    # for the whole match.
    slot_count(): ulong {
        return (group_count + 1) * 2;
    }

    # Whether class `index` holds the code point `value`.
    class_contains(index: ulong, value: uint): bool {
        var low = class_starts[index];
        var high = class_starts[index + 1];
        var key = ((value as ulong) << 32) | 4294967295;
        # The ranges are sorted and disjoint: find the last that starts at or
        # before `value`.
        while (low < high) {
            var middle = low + (high - low) / 2;
            if (ranges[middle] <= key) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        if (low == class_starts[index]) {
            return false;
        }
        return _regex_range_high(ranges[low - 1]) >= value;
    }
}

# Compiles `pattern` into a program, or gives the reason it is invalid.
export _regex_compile(pattern: String): Result<_RegexProgram> {
    var parser = _RegexParser(pattern);
    var tree = parser.parse();
    if (parser.failed) {
        return Result<_RegexProgram>.err(Error($"invalid regex '{pattern}': {parser.error}"));
    }
    var compiler = _RegexCompiler();
    var program = compiler.program;
    program.group_count = parser.group_count;
    program.names = parser.names;
    program.anchored = _regex_starts_anchored(tree);
    compiler.emit(_REGEX_OP_SAVE, 0, 0);
    compiler.compile(tree);
    compiler.emit(_REGEX_OP_SAVE, 1, 0);
    compiler.emit(_REGEX_OP_MATCH, 0, 0);
    if (compiler.too_large) {
        return Result<_RegexProgram>.err(
            Error($"invalid regex '{pattern}': the compiled pattern exceeds {_REGEX_MAX_INSTRUCTIONS} instructions")
        );
    }
    return Result<_RegexProgram>.ok(program);
}

# Whether every match of `node` must start at the start of the text.
_regex_starts_anchored(node: _RegexNode): bool {
    if (node.kind == _REGEX_NODE_ASSERT) {
        return node.value == (_REGEX_AT_TEXT_START as uint);
    }
    if (node.kind == _REGEX_NODE_CONCAT && node.children.count() > 0) {
        return _regex_starts_anchored(node.children[0]);
    }
    if (node.kind == _REGEX_NODE_GROUP) {
        return _regex_starts_anchored(node.children[0]);
    }
    return false;
}

export struct _RegexCompiler {
    var program: _RegexProgram;
    var too_large: bool;

    construct() {
        program = _RegexProgram();
        too_large = false;
    }

    # Appends an instruction and returns its index.
    emit(op: int, a: ulong, b: ulong): ulong {
        var index = program.ops.count();
        if (index >= _REGEX_MAX_INSTRUCTIONS) {
            too_large = true;
            return index;
        }
        program.ops.append(op);
        program.a.append(a);
        program.b.append(b);
        return index;
    }

    # The index the next instruction gets.
    here(): ulong {
        return program.ops.count();
    }

    _patch_a(index: ulong, target: ulong) {
        if (index < program.a.count()) {
            program.a[index] = target;
        }
    }

    _patch_b(index: ulong, target: ulong) {
        if (index < program.b.count()) {
            program.b[index] = target;
        }
    }

    compile(node: _RegexNode) {
        if (too_large) {
            return;
        }
        var kind = node.kind;
        if (kind == _REGEX_NODE_CHAR) {
            emit(_REGEX_OP_CHAR, node.value as ulong, 0);
        } else if (kind == _REGEX_NODE_ANY) {
            emit(node.value == 1 ? _REGEX_OP_ANY_NEWLINE : _REGEX_OP_ANY, 0, 0);
        } else if (kind == _REGEX_NODE_CLASS) {
            _compile_class(node.ranges);
        } else if (kind == _REGEX_NODE_ASSERT) {
            emit(_REGEX_OP_ASSERT, node.value as ulong, 0);
        } else if (kind == _REGEX_NODE_GROUP) {
            if (node.group >= 0) {
                emit(_REGEX_OP_SAVE, (node.group as ulong) * 2, 0);
            }
            compile(node.children[0]);
            if (node.group >= 0) {
                emit(_REGEX_OP_SAVE, (node.group as ulong) * 2 + 1, 0);
            }
        } else if (kind == _REGEX_NODE_CONCAT) {
            for (var child in node.children) {
                compile(child);
            }
        } else if (kind == _REGEX_NODE_ALTERNATE) {
            _compile_alternate(node.children);
        } else if (kind == _REGEX_NODE_REPEAT) {
            _compile_repeat(node);
        }
    }

    _compile_class(ranges: ulong[]) {
        if (ranges.count() == 1 && _regex_range_low(ranges[0]) == _regex_range_high(ranges[0])) {
            emit(_REGEX_OP_CHAR, _regex_range_low(ranges[0]) as ulong, 0);
            return;
        }
        var index = program.class_starts.count() - 1;
        for (var range in ranges) {
            program.ranges.append(range);
        }
        program.class_starts.append(program.ranges.count());
        emit(_REGEX_OP_CLASS, index, 0);
    }

    # a|b|c: SPLIT L1, next; L1: a; JUMP end; next: SPLIT L2, L3; ...
    _compile_alternate(branches: _RegexNode[]) {
        var jumps = Array<ulong>();
        var count = branches.count();
        ulong index = 0;
        while (index + 1 < count) {
            var split = emit(_REGEX_OP_SPLIT, 0, 0);
            _patch_a(split, here());
            compile(branches[index]);
            jumps.append(emit(_REGEX_OP_JUMP, 0, 0));
            _patch_b(split, here());
            index += 1;
        }
        compile(branches[count - 1]);
        for (var jump in jumps) {
            _patch_a(jump, here());
        }
    }

    _compile_repeat(node: _RegexNode) {
        var child = node.children[0];
        var greedy = node.greedy;
        if (node.max < 0) {
            if (node.min == 0) {
                # L: SPLIT body, end; body: child; JUMP L; end:
                var loop = emit(_REGEX_OP_SPLIT, 0, 0);
                compile(child);
                emit(_REGEX_OP_JUMP, loop, 0);
                _set_split(loop, greedy, loop + 1, here());
                return;
            }
            # x{n,} is n - 1 copies of x, then x with a SPLIT back to it.
            ulong copy = 1;
            while (copy < node.min && !too_large) {
                compile(child);
                copy += 1;
            }
            var body = here();
            compile(child);
            var split = emit(_REGEX_OP_SPLIT, 0, 0);
            _set_split(split, greedy, body, here());
            return;
        }
        ulong required = 0;
        while (required < node.min && !too_large) {
            compile(child);
            required += 1;
        }
        # Each optional copy: SPLIT body, end; body: child.
        var splits = Array<ulong>();
        var optional = (node.max as ulong) - node.min;
        ulong done = 0;
        while (done < optional && !too_large) {
            var split = emit(_REGEX_OP_SPLIT, 0, 0);
            splits.append(split);
            compile(child);
            done += 1;
        }
        var end = here();
        for (var split in splits) {
            _set_split(split, greedy, split + 1, end);
        }
    }

    # Points the SPLIT at `index` to `body` and `end`, preferring `body` when
    # greedy.
    _set_split(index: ulong, greedy: bool, body: ulong, end: ulong) {
        if (greedy) {
            _patch_a(index, body);
            _patch_b(index, end);
        } else {
            _patch_a(index, end);
            _patch_b(index, body);
        }
    }
}
