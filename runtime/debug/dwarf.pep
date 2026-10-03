# Reading a DWARF line table (`.debug_line`), shared by the ELF (Linux)
# and Mach-O (macOS) symbolizers.

import "backtrace";

# The little-endian unsigned integer of `size` (1-8) bytes at `data + offset`.
export _debug_read(data: __ptr<u8>, offset: ulong, size: ulong): ulong {
    ulong value = 0;
    ulong index = 0;
    while (index < size) {
        value = value | ((data[offset + index] as ulong) << (index * 8));
        index = index + 1;
    }
    return value;
}

# A bounds-checked reader over `data[position..end]`. A read past `end`
# returns 0 and sets `failed`, so a damaged table ends the walk instead of
# reading outside the section.
export struct _DwarfCursor {
    var _data: __ptr<u8>;
    var position: ulong;
    var end: ulong;
    var failed: bool;

    construct(data: __ptr<u8>, position: ulong, end: ulong) {
        _data = data;
        this.position = position;
        this.end = end;
        failed = false;
    }

    # The next `size` bytes as a little-endian unsigned integer.
    read_fixed(size: ulong): ulong {
        if (failed || size > end - position || position > end) {
            failed = true;
            return 0;
        }
        var value = _debug_read(_data, position, size);
        position = position + size;
        return value;
    }

    # An unsigned LEB128 number.
    read_uleb(): ulong {
        ulong value = 0;
        ulong shift = 0;
        while (true) {
            var b = read_fixed(1);
            if (failed) {
                return 0;
            }
            if (shift < 64) {
                value = value | ((b & 0x7f) << shift);
            }
            shift = shift + 7;
            if ((b & 0x80) == 0) {
                return value;
            }
        }
        return value;
    }

    # A signed LEB128 number.
    read_sleb(): long {
        ulong value = 0;
        ulong shift = 0;
        ulong b = 0;
        while (true) {
            b = read_fixed(1);
            if (failed) {
                return 0;
            }
            if (shift < 64) {
                value = value | ((b & 0x7f) << shift);
            }
            shift = shift + 7;
            if ((b & 0x80) == 0) {
                break;
            }
        }
        if (shift < 64 && (b & 0x40) != 0) {
            value = value | (0xffffffffffffffff << shift);
        }
        return value as long;
    }

    # A NUL-terminated string.
    read_string(): String {
        var start = position;
        while (position < end && _data[position] != 0) {
            position = position + 1;
        }
        if (position >= end) {
            failed = true;
            return String();
        }
        var text = String(unsafe_cast<__ptr<char>>(_data + start), position - start);
        position = position + 1;
        return text;
    }

    # Moves `size` bytes on.
    skip(size: ulong) {
        if (failed || size > end - position) {
            failed = true;
            return;
        }
        position = position + size;
    }
}

# A line-table row: the source position of the code from `address` on.
struct _DwarfRow {
    var address: ulong;
    var file: ulong;
    var line: ulong;
    var column: ulong;

    construct() {
        address = 0;
        file = 1;
        line = 1;
        column = 0;
    }
}

# Fills the file, line and column of each frame whose lookup address,
# `targets[i]` (an address as the line table writes it; 0 to skip the
# frame), the `.debug_line` section `data[0..size]` covers. Reads DWARF
# versions 2 to 4, which the compiler emits.
export _debug_dwarf_lines(data: __ptr<u8>, size: ulong, targets: Array<ulong>, frames: Array<StackFrame>) {
    # The row each target falls in, by the closest row start found so far.
    var best = Array<ulong>();
    for (var target in targets) {
        best.append(0);
    }
    ulong unit = 0;
    while (unit + 4 <= size) {
        var cursor = _DwarfCursor(data, unit, size);
        ulong length = cursor.read_fixed(4);
        ulong offset_size = 4;
        if (length == 0xffffffff) {
            length = cursor.read_fixed(8);
            offset_size = 8;
        }
        if (cursor.failed || length > size - cursor.position) {
            return;
        }
        var unit_end = cursor.position + length;
        unit = unit_end;
        cursor.end = unit_end;
        var version = cursor.read_fixed(2);
        if (version < 2 || version > 4) {
            continue;
        }
        var header_length = cursor.read_fixed(offset_size);
        var program = cursor.position + header_length;
        var minimum_length = cursor.read_fixed(1);
        if (version >= 4) {
            cursor.read_fixed(1);
        }
        cursor.read_fixed(1);
        var line_base = cursor.read_fixed(1);
        long base = line_base >= 128 ? (line_base as long) - 256 : line_base as long;
        var line_range = cursor.read_fixed(1);
        var opcode_base = cursor.read_fixed(1);
        var lengths = Array<ulong>();
        ulong index = 1;
        while (index < opcode_base) {
            lengths.append(cursor.read_fixed(1));
            index = index + 1;
        }
        var directories = Array<String>();
        while (!cursor.failed) {
            var directory = cursor.read_string();
            if (directory.is_empty) {
                break;
            }
            directories.append(directory);
        }
        var files = Array<String>();
        while (!cursor.failed) {
            var name = cursor.read_string();
            if (name.is_empty) {
                break;
            }
            var directory = cursor.read_uleb();
            cursor.read_uleb();
            cursor.read_uleb();
            files.append(_debug_join_path(directories, directory, name));
        }
        if (cursor.failed || line_range == 0 || program > unit_end) {
            continue;
        }
        cursor.position = program;
        _debug_run_line_program(
            cursor, minimum_length, base, line_range, opcode_base, lengths, files, targets, best, frames
        );
    }
}

# The path of file `name` in directory `directory` (1-based; 0 is the
# compilation directory, which leaves `name` as given).
_debug_join_path(directories: Array<String>, directory: ulong, name: String): String {
    if (directory == 0 || directory > directories.count || name.starts_with("/")) {
        return name;
    }
    var folder = directories[directory - 1];
    if (folder.ends_with("/")) {
        return $"{folder}{name}";
    }
    return $"{folder}/{name}";
}

# Runs one unit's line-number program, matching each row range against the
# targets.
_debug_run_line_program(
    cursor: _DwarfCursor,
    minimum_length: ulong,
    line_base: long,
    line_range: ulong,
    opcode_base: ulong,
    lengths: Array<ulong>,
    files: Array<String>,
    targets: Array<ulong>,
    best: Array<ulong>,
    frames: Array<StackFrame>
) {
    var row = _DwarfRow();
    # The previous row of this sequence; `started` is false at a sequence's
    # start, when there is none.
    var previous = _DwarfRow();
    var started = false;
    while (!cursor.failed && cursor.position < cursor.end) {
        var opcode = cursor.read_fixed(1);
        var emit = false;
        var end_sequence = false;
        if (opcode >= opcode_base) {
            var adjusted = opcode - opcode_base;
            row.address = row.address + (adjusted / line_range) * minimum_length;
            row.line = ((row.line as long) + line_base + ((adjusted % line_range) as long)) as ulong;
            emit = true;
        } else if (opcode == 0) {
            var length = cursor.read_uleb();
            if (length == 0) {
                continue;
            }
            var extended = cursor.read_fixed(1);
            if (extended == 1) {
                emit = true;
                end_sequence = true;
            } else if (extended == 2) {
                row.address = cursor.read_fixed(length - 1);
            } else {
                cursor.skip(length - 1);
            }
        } else if (opcode == 1) {
            emit = true;
        } else if (opcode == 2) {
            row.address = row.address + cursor.read_uleb() * minimum_length;
        } else if (opcode == 3) {
            row.line = ((row.line as long) + cursor.read_sleb()) as ulong;
        } else if (opcode == 4) {
            row.file = cursor.read_uleb();
        } else if (opcode == 5) {
            row.column = cursor.read_uleb();
        } else if (opcode == 8) {
            row.address = row.address + ((255 - opcode_base) / line_range) * minimum_length;
        } else if (opcode == 9) {
            row.address = row.address + cursor.read_fixed(2);
        } else if (opcode == 6 || opcode == 7 || opcode == 10 || opcode == 11) {
            # is_stmt, basic_block, prologue_end, epilogue_begin: no operands
        } else {
            ulong operand = 0;
            while (operand < lengths[opcode - 1]) {
                cursor.read_uleb();
                operand = operand + 1;
            }
        }
        if (!emit) {
            continue;
        }
        if (started) {
            _debug_match_rows(previous, row.address, files, targets, best, frames);
        }
        if (end_sequence) {
            row = _DwarfRow();
            started = false;
        } else {
            previous.address = row.address;
            previous.file = row.file;
            previous.line = row.line;
            previous.column = row.column;
            started = true;
        }
    }
}

# Gives each target in `[row.address, end)` the row's position, unless a
# closer row (a later start) already matched it.
_debug_match_rows(
    row: _DwarfRow,
    end: ulong,
    files: Array<String>,
    targets: Array<ulong>,
    best: Array<ulong>,
    frames: Array<StackFrame>
) {
    if (row.line == 0) {
        return;
    }
    ulong index = 0;
    while (index < targets.count) {
        var target = targets[index];
        if (target != 0 && target >= row.address && target < end && row.address >= best[index]) {
            best[index] = row.address;
            var frame = frames[index];
            frame.file = row.file >= 1 && row.file <= files.count ? files[row.file - 1] : "";
            frame.line = row.line as int;
            frame.column = row.column as int;
        }
        index = index + 1;
    }
}
