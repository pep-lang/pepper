# The matcher: a Pike VM, which runs every thread of a program in lock step
# over the text, one code point at a time. It never backtracks, so a search
# takes O(text size * program size) time whatever the pattern.

import "compile";
import "syntax";

# The threads at one text position, in priority order, each with the
# capture slots it carries. A sparse set: membership by instruction index
# in O(1), and clearing in O(1).
export struct _RegexThreads {
    var sparse: ulong[];
    var dense: ulong[];
    var count: ulong;
    # `slot_count` capture positions for each instruction, -1 when unset.
    var slots: long[];

    construct(size: ulong, slot_count: ulong) {
        sparse = Array<ulong>(size);
        dense = Array<ulong>(size);
        ulong index = 0;
        while (index < size) {
            sparse.append(0);
            dense.append(0);
            index += 1;
        }
        count = 0;
        var total = size * slot_count;
        slots = Array<long>(total);
        index = 0;
        while (index < total) {
            slots.append(-1);
            index += 1;
        }
    }

    contains(pc: ulong): bool {
        var at = sparse[pc];
        return at < count && dense[at] == pc;
    }

    insert(pc: ulong) {
        sparse[pc] = count;
        dense[count] = pc;
        count += 1;
    }
}

# Runs one program, keeping its scratch space between searches.
export struct _RegexMatcher {
    var program: _RegexProgram;
    var _current: _RegexThreads;
    var _next: _RegexThreads;
    var _slot_count: ulong;
    var _captures: long[];
    # Instruction indexes still to visit while adding a thread, and capture
    # slots to restore (encoded as `-(slot + 1)` above the old value).
    var _stack: long[];

    construct(program: _RegexProgram) {
        this.program = program;
        var size = program.op_count;
        _slot_count = program.slot_count();
        _current = _RegexThreads(size, _slot_count);
        _next = _RegexThreads(size, _slot_count);
        _captures = Array<long>(_slot_count);
        ulong index = 0;
        while (index < _slot_count) {
            _captures.append(-1);
            index += 1;
        }
        _stack = Array<long>();
    }

    # Finds the leftmost match starting at or after byte `from` of `text`.
    # Returns its capture slots: a start and end byte offset for the whole
    # match and each group, -1 for a group that did not take part. With
    # `earliest`, stops at the first position where any match ends, and
    # returns only whether there is one (the slots are not meaningful).
    search(text: String, from: ulong, earliest: bool): long[]? {
        var size = text.size;
        __ptr<u8> data = unsafe_cast<__ptr<u8>>(text._data);
        _current.count = 0;
        var position = from;
        var matched = false;
        var best = Array<long>();
        while (true) {
            if (!matched && (!program.anchored || position == 0)) {
                _reset_captures();
                _add(_current, 0, position, data, size);
            }
            if (_current.count == 0 && (matched || program.anchored || position >= size)) {
                break;
            }
            uint value = 0;
            ulong width = 0;
            var at_end = position >= size;
            if (!at_end) {
                var (decoded, run) = _regex_decode(data, position, size);
                value = decoded;
                width = run;
            }
            _next.count = 0;
            ulong index = 0;
            while (index < _current.count) {
                var pc = _current.dense[index];
                index += 1;
                var op = program.ops[pc];
                var step = false;
                if (op == _REGEX_OP_MATCH) {
                    matched = true;
                    if (earliest) {
                        return Optional<long[]>.Value(best);
                    }
                    best = _copy_slots(_current, pc);
                    # Lower-priority threads can only give a worse match.
                    break;
                } else if (at_end) {
                    step = false;
                } else if (op == _REGEX_OP_CHAR) {
                    step = program.a[pc] == (value as ulong);
                } else if (op == _REGEX_OP_ANY) {
                    step = value != 10;
                } else if (op == _REGEX_OP_ANY_NEWLINE) {
                    step = true;
                } else if (op == _REGEX_OP_CLASS) {
                    step = program.class_contains(program.a[pc], value);
                }
                if (step) {
                    _load_captures(_current, pc);
                    _add(_next, pc + 1, position + width, data, size);
                }
            }
            if (at_end) {
                break;
            }
            var swap = _current;
            _current = _next;
            _next = swap;
            position += width;
        }
        if (!matched) {
            return Optional<long[]>.Empty;
        }
        return Optional<long[]>.Value(best);
    }

    _reset_captures() {
        ulong index = 0;
        while (index < _slot_count) {
            _captures[index] = -1;
            index += 1;
        }
    }

    _load_captures(threads: _RegexThreads, pc: ulong) {
        var base = pc * _slot_count;
        ulong index = 0;
        while (index < _slot_count) {
            _captures[index] = threads.slots[base + index];
            index += 1;
        }
    }

    _copy_slots(threads: _RegexThreads, pc: ulong): long[] {
        var result = Array<long>(_slot_count);
        var base = pc * _slot_count;
        ulong index = 0;
        while (index < _slot_count) {
            result.append(threads.slots[base + index]);
            index += 1;
        }
        return result;
    }

    # Adds the thread at instruction `start` to `threads`, following jumps,
    # splits, saves and assertions to the instructions that consume text,
    # with `_captures` as its capture slots. Uses an explicit stack, since
    # the program's shape comes from the pattern.
    _add(threads: _RegexThreads, start: ulong, position: ulong, data: __ptr<u8>, size: ulong) {
        _stack.clear();
        _stack.append(start as long);
        while (_stack.count > 0) {
            var top = _stack.pop();
            if (top < 0) {
                var slot = (-top - 1) as ulong;
                _captures[slot] = _stack.pop();
                continue;
            }
            var pc = top as ulong;
            if (threads.contains(pc)) {
                continue;
            }
            threads.insert(pc);
            var op = program.ops[pc];
            if (op == _REGEX_OP_JUMP) {
                _stack.append(program.a[pc] as long);
            } else if (op == _REGEX_OP_SPLIT) {
                _stack.append(program.b[pc] as long);
                _stack.append(program.a[pc] as long);
            } else if (op == _REGEX_OP_SAVE) {
                var slot = program.a[pc];
                _stack.append(_captures[slot]);
                _stack.append(-((slot as long) + 1));
                _captures[slot] = position as long;
                _stack.append((pc + 1) as long);
            } else if (op == _REGEX_OP_ASSERT) {
                if (_regex_assert(program.a[pc] as int, data, size, position)) {
                    _stack.append((pc + 1) as long);
                }
            } else {
                var base = pc * _slot_count;
                ulong index = 0;
                while (index < _slot_count) {
                    threads.slots[base + index] = _captures[index];
                    index += 1;
                }
            }
        }
    }
}

# Whether the `_REGEX_AT_` assertion `kind` holds at byte `position` of the
# `size` bytes at `data`.
_regex_assert(kind: int, data: __ptr<u8>, size: ulong, position: ulong): bool {
    if (kind == _REGEX_AT_TEXT_START) {
        return position == 0;
    }
    if (kind == _REGEX_AT_TEXT_END) {
        return position == size;
    }
    if (kind == _REGEX_AT_LINE_START) {
        return position == 0 || data[position - 1] == 10;
    }
    if (kind == _REGEX_AT_LINE_END) {
        return position == size || data[position] == 10;
    }
    var before = position > 0 && _regex_is_word(data[position - 1]);
    var after = position < size && _regex_is_word(data[position]);
    if (kind == _REGEX_AT_WORD) {
        return before != after;
    }
    return before == after;
}

# Whether `value` is an ASCII word character: a letter, digit or '_'.
_regex_is_word(value: u8): bool {
    return (value >= 'a' && value <= 'z')
        || (value >= 'A' && value <= 'Z')
        || (value >= '0' && value <= '9')
        || value == '_';
}
