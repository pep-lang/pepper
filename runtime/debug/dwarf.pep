# Reading DWARF, shared by the ELF (Linux) and Mach-O (macOS) symbolizers:
# the line table (`.debug_line`) gives each address its source position,
# and the debug info (`.debug_info`) the inlined calls it is inside.

import "backtrace";

# The little-endian unsigned integer of `size` (1-8) bytes at `data + offset`.
_debug_read(data: __ptr<u8>, offset: ulong, size: ulong): ulong {
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
struct _DwarfCursor {
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

# The header of one unit of a `.debug_line` section: where its line-number
# program is, how to run it, and the files its rows name.
struct _DwarfLineHeader {
    var valid: bool;
    # Where the program starts and the unit ends, as section offsets.
    var program: ulong;
    var unit_end: ulong;
    var minimum_length: ulong;
    var line_base: long;
    var line_range: ulong;
    var opcode_base: ulong;
    # The operand count of each standard opcode, from opcode 1.
    var lengths: Array<ulong>;
    # Each file's path, for file number 1 on.
    var files: Array<String>;

    construct() {
        valid = false;
        program = 0;
        unit_end = 0;
        minimum_length = 1;
        line_base = 0;
        line_range = 0;
        opcode_base = 0;
        lengths = Array<ulong>();
        files = Array<String>();
    }

    # Reads the header of the unit at `offset` in `data[0..size]`. Sets
    # `unit_end` (0 when even the length is damaged) and, for a unit of
    # DWARF version 2 to 4 it could read, `valid`.
    read(data: __ptr<u8>, size: ulong, offset: ulong) {
        var cursor = _DwarfCursor(data, offset, size);
        ulong length = cursor.read_fixed(4);
        ulong offset_size = 4;
        if (length == 0xffffffff) {
            length = cursor.read_fixed(8);
            offset_size = 8;
        }
        if (cursor.failed || length > size - cursor.position) {
            return;
        }
        unit_end = cursor.position + length;
        cursor.end = unit_end;
        var version = cursor.read_fixed(2);
        if (version < 2 || version > 4) {
            return;
        }
        var header_length = cursor.read_fixed(offset_size);
        program = cursor.position + header_length;
        minimum_length = cursor.read_fixed(1);
        if (version >= 4) {
            cursor.read_fixed(1);
        }
        cursor.read_fixed(1);
        var base = cursor.read_fixed(1);
        line_base = base >= 128 ? (base as long) - 256 : base as long;
        line_range = cursor.read_fixed(1);
        opcode_base = cursor.read_fixed(1);
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
        valid = !cursor.failed && line_range != 0 && program <= unit_end;
    }
}

# Fills the file, line and column of each frame whose lookup address,
# `targets[i]` (an address as the line table writes it; 0 to skip the
# frame), the `.debug_line` section `data[0..size]` covers. Reads DWARF
# versions 2 to 4, which the compiler emits.
_debug_dwarf_lines(data: __ptr<u8>, size: ulong, targets: Array<ulong>, frames: Array<StackFrame>) {
    # The row each target falls in, by the closest row start found so far.
    var best = Array<ulong>();
    for (var target in targets) {
        best.append(0);
    }
    ulong unit = 0;
    while (unit + 4 <= size) {
        var header = _DwarfLineHeader();
        header.read(data, size, unit);
        if (header.unit_end == 0) {
            return;
        }
        unit = header.unit_end;
        if (!header.valid) {
            continue;
        }
        var cursor = _DwarfCursor(data, header.program, header.unit_end);
        _debug_run_line_program(cursor, header, targets, best, frames);
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
    cursor: _DwarfCursor, header: _DwarfLineHeader, targets: Array<ulong>, best: Array<ulong>, frames: Array<StackFrame>
) {
    var minimum_length = header.minimum_length;
    var line_base = header.line_base;
    var line_range = header.line_range;
    var opcode_base = header.opcode_base;
    var lengths = header.lengths;
    var files = header.files;
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

# The DWARF sections a backtrace reads, as the program maps them; a section
# the program lacks has size 0.
struct _DwarfSections {
    var info: __ptr<u8>;
    var info_size: ulong;
    var abbrev: __ptr<u8>;
    var abbrev_size: ulong;
    var strings: __ptr<u8>;
    var strings_size: ulong;
    var ranges: __ptr<u8>;
    var ranges_size: ulong;
    var line: __ptr<u8>;
    var line_size: ulong;

    construct() {
        info = __null;
        info_size = 0;
        abbrev = __null;
        abbrev_size = 0;
        strings = __null;
        strings_size = 0;
        ranges = __null;
        ranges_size = 0;
        line = __null;
        line_size = 0;
    }

    # Records section `name` (spelled as ELF does, `.debug_info`) at
    # `data[0..size]`; other names are ignored.
    set(name: String, data: __ptr<u8>, size: ulong) {
        if (name == ".debug_info") {
            info = data;
            info_size = size;
        } else if (name == ".debug_abbrev") {
            abbrev = data;
            abbrev_size = size;
        } else if (name == ".debug_str") {
            strings = data;
            strings_size = size;
        } else if (name == ".debug_ranges") {
            ranges = data;
            ranges_size = size;
        } else if (name == ".debug_line") {
            line = data;
            line_size = size;
        }
    }
}

# Resolves frames from DWARF: fills each frame's source position from the
# line table, then expands each frame whose address is inside inlined code
# into one frame per inlined call, innermost first, as `addr2line -i` does.
# `targets[i]` is frame i's lookup address as the debug info writes it, or
# 0 to leave the frame as it is.
#
# @returns the frames, with the inlined ones added
_debug_dwarf_frames(sections: _DwarfSections, targets: Array<ulong>, frames: Array<StackFrame>): Array<StackFrame> {
    if (sections.line_size > 0) {
        _debug_dwarf_lines(sections.line, sections.line_size, targets, frames);
    }
    if (sections.info_size == 0 || sections.abbrev_size == 0) {
        return frames;
    }
    var chains = _debug_dwarf_inline_chains(sections, targets);
    var all = Array<StackFrame>();
    ulong index = 0;
    while (index < frames.count) {
        var frame = frames[index];
        var chain = chains[index];
        if (!chain.is_empty) {
            # The innermost inlined function is at the line table's
            # position; each caller is at the call site of the function it
            # inlined, and the real frame at the outermost call site.
            var level = chain.count;
            var position = frame;
            while (level > 0) {
                var call = chain[level - 1];
                var inner = StackFrame(frame.address);
                inner.function = call.function;
                inner.file = position.file;
                inner.line = position.line;
                inner.column = position.column;
                inner.inlined = true;
                all.append(inner);
                position = StackFrame(frame.address);
                position.file = call.file;
                position.line = call.line;
                position.column = call.column;
                level = level - 1;
            }
            frame.file = position.file;
            frame.line = position.line;
            frame.column = position.column;
        }
        all.append(frame);
        index = index + 1;
    }
    return all;
}

# One inlined call: the function inlined, and where its caller called it.
struct _DwarfInline {
    var function: String;
    var file: String;
    var line: int;
    var column: int;

    construct(function: String, file: String, line: int, column: int) {
        this.function = function;
        this.file = file;
        this.line = line;
        this.column = column;
    }
}

# An abbreviation: a DIE's tag, whether it has children, and its
# attributes as (name, form) pairs.
struct _DwarfAbbrev {
    var tag: ulong;
    var children: bool;
    var attributes: Array<ulong>;

    construct() {
        tag = 0;
        children = false;
        attributes = Array<ulong>();
    }
}

# A `.debug_info` unit's header and what its DIEs are read with.
struct _DwarfUnit {
    # The section offsets of the unit's header and of its end.
    var offset: ulong;
    var end: ulong;
    # Where its first DIE starts.
    var first: ulong;
    var version: ulong;
    var address_size: ulong;
    var offset_size: ulong;
    var abbrev_offset: ulong;
    # Abbreviations by code; code 0, and codes the table skips, have tag 0.
    var abbrevs: Array<_DwarfAbbrev>;
    # The unit's base address (its DIE's `DW_AT_low_pc`), for its ranges.
    var base: ulong;
    # Its line table's offset (`DW_AT_stmt_list`), and that table's files
    # once `files_read`.
    var line_offset: ulong;
    var has_lines: bool;
    var files: Array<String>;
    var files_read: bool;

    construct() {
        offset = 0;
        end = 0;
        first = 0;
        version = 0;
        address_size = 8;
        offset_size = 4;
        abbrev_offset = 0;
        abbrevs = Array<_DwarfAbbrev>();
        base = 0;
        line_offset = 0;
        has_lines = false;
        files = Array<String>();
        files_read = false;
    }

    # Reads the header of the unit at section offset `at`. Sets `end` (0
    # when even the length is damaged) and returns whether the unit is one
    # of DWARF version 2 to 4 whose abbreviations it read.
    read(sections: _DwarfSections, at: ulong): bool {
        offset = at;
        end = 0;
        var cursor = _DwarfCursor(sections.info, at, sections.info_size);
        ulong length = cursor.read_fixed(4);
        offset_size = 4;
        if (length == 0xffffffff) {
            length = cursor.read_fixed(8);
            offset_size = 8;
        }
        if (cursor.failed || length > sections.info_size - cursor.position) {
            return false;
        }
        end = cursor.position + length;
        cursor.end = end;
        version = cursor.read_fixed(2);
        if (version < 2 || version > 4) {
            return false;
        }
        var table = cursor.read_fixed(offset_size);
        address_size = cursor.read_fixed(1);
        first = cursor.position;
        base = 0;
        has_lines = false;
        files_read = false;
        if (cursor.failed || (address_size != 4 && address_size != 8)) {
            return false;
        }
        if (abbrevs.is_empty || table != abbrev_offset) {
            abbrev_offset = table;
            return _read_abbrevs(sections);
        }
        return true;
    }

    _read_abbrevs(sections: _DwarfSections): bool {
        abbrevs = Array<_DwarfAbbrev>();
        abbrevs.append(_DwarfAbbrev());
        var cursor = _DwarfCursor(sections.abbrev, abbrev_offset, sections.abbrev_size);
        while (!cursor.failed) {
            var code = cursor.read_uleb();
            if (code == 0) {
                break;
            }
            var abbrev = _DwarfAbbrev();
            abbrev.tag = cursor.read_uleb();
            abbrev.children = cursor.read_fixed(1) != 0;
            while (!cursor.failed) {
                var name = cursor.read_uleb();
                var form = cursor.read_uleb();
                if (name == 0 && form == 0) {
                    break;
                }
                abbrev.attributes.append(name);
                abbrev.attributes.append(form);
            }
            # A code far beyond the table's size is damage.
            if (code > 0x100000) {
                abbrevs = Array<_DwarfAbbrev>();
                return false;
            }
            while (abbrevs.count <= code) {
                abbrevs.append(_DwarfAbbrev());
            }
            abbrevs[code] = abbrev;
        }
        if (cursor.failed) {
            abbrevs = Array<_DwarfAbbrev>();
            return false;
        }
        return true;
    }

    # The path of file number `file` of the unit's line table, or an empty
    # String.
    file_name(sections: _DwarfSections, file: ulong): String {
        if (!files_read) {
            files_read = true;
            if (has_lines && sections.line_size > 0) {
                var header = _DwarfLineHeader();
                header.read(sections.line, sections.line_size, line_offset);
                if (header.valid) {
                    files = header.files;
                }
            }
        }
        return file >= 1 && file <= files.count ? files[file - 1] : "";
    }
}

# The attributes of one DIE that backtraces read.
struct _DwarfDie {
    var tag: ulong;
    var children: bool;
    var name: String;
    var low: ulong;
    var has_low: bool;
    var high: ulong;
    var has_high: bool;
    # `DW_AT_high_pc` is an offset from `low` (any form but an address).
    var high_is_size: bool;
    var ranges: ulong;
    var has_ranges: bool;
    # The section offset of the DIE that names this one
    # (`DW_AT_abstract_origin` or `DW_AT_specification`).
    var origin: ulong;
    var has_origin: bool;
    var line_offset: ulong;
    var has_lines: bool;
    var call_file: ulong;
    var call_line: ulong;
    var call_column: ulong;

    construct() {
        name = String();
        clear();
    }

    clear() {
        tag = 0;
        children = false;
        if (!name.is_empty) {
            name = String();
        }
        low = 0;
        has_low = false;
        high = 0;
        has_high = false;
        high_is_size = false;
        ranges = 0;
        has_ranges = false;
        origin = 0;
        has_origin = false;
        line_offset = 0;
        has_lines = false;
        call_file = 0;
        call_line = 0;
        call_column = 0;
    }

    # Reads the DIE at the cursor. Returns false at a null entry (the end of
    # a list of siblings) or on damage, which sets `cursor.failed`.
    read(cursor: _DwarfCursor, unit: _DwarfUnit, sections: _DwarfSections): bool {
        clear();
        var code = cursor.read_uleb();
        if (code == 0 || cursor.failed) {
            return false;
        }
        if (code >= unit.abbrevs.count || unit.abbrevs[code].tag == 0) {
            cursor.failed = true;
            return false;
        }
        var abbrev = unit.abbrevs[code];
        tag = abbrev.tag;
        children = abbrev.children;
        var attributes = abbrev.attributes;
        ulong index = 0;
        while (index + 1 < attributes.count && !cursor.failed) {
            var attribute = attributes[index];
            var form = attributes[index + 1];
            index = index + 2;
            # DW_FORM_indirect
            while (form == 0x16 && !cursor.failed) {
                form = cursor.read_uleb();
            }
            # DW_FORM_string
            if (form == 0x08) {
                var text = cursor.read_string();
                if (attribute == 0x03) {
                    name = text;
                }
                continue;
            }
            var value = _debug_dwarf_form(cursor, form, unit);
            if (attribute == 0x03 && form == 0x0e) {
                # DW_AT_name as DW_FORM_strp
                name = _debug_dwarf_string(sections, value);
            } else if (attribute == 0x11) {
                low = value;
                has_low = true;
            } else if (attribute == 0x12) {
                high = value;
                has_high = true;
                high_is_size = form != 0x01;
            } else if (attribute == 0x55) {
                ranges = value;
                has_ranges = true;
            } else if (attribute == 0x31 || attribute == 0x47) {
                # A reference within the unit (ref1 to ref_udata) counts
                # from the unit's start; ref_addr from the section's.
                origin = form >= 0x11 && form <= 0x15 ? unit.offset + value : value;
                has_origin = true;
            } else if (attribute == 0x10) {
                line_offset = value;
                has_lines = true;
            } else if (attribute == 0x58) {
                call_file = value;
            } else if (attribute == 0x59) {
                call_line = value;
            } else if (attribute == 0x57) {
                call_column = value;
            }
        }
        return !cursor.failed;
    }

    # Sets `hits[i]` for each target the DIE's code covers, and returns
    # whether it covers any.
    covers(unit: _DwarfUnit, sections: _DwarfSections, targets: Array<ulong>, hits: Array<bool>): bool {
        var any = false;
        ulong index = 0;
        while (index < targets.count) {
            hits[index] = false;
            index = index + 1;
        }
        if (has_low && has_high) {
            var end = high_is_size ? low + high : high;
            return _debug_dwarf_hit(low, end, targets, hits);
        }
        if (!has_ranges || ranges >= sections.ranges_size) {
            return false;
        }
        # A `.debug_ranges` list: (start, end) pairs, relative to a base
        # address that a pair starting with all ones changes, up to (0, 0).
        var cursor = _DwarfCursor(sections.ranges, ranges, sections.ranges_size);
        var size = unit.address_size;
        ulong all_ones = size == 8 ? 0xffffffffffffffff : 0xffffffff;
        var base = unit.base;
        while (!cursor.failed) {
            var start = cursor.read_fixed(size);
            var end = cursor.read_fixed(size);
            if (cursor.failed || (start == 0 && end == 0)) {
                break;
            }
            if (start == all_ones) {
                base = end;
            } else if (_debug_dwarf_hit(base + start, base + end, targets, hits)) {
                any = true;
            }
        }
        return any;
    }
}

# Sets `hits[i]` for each nonzero target in `[start, end)`; returns whether
# there was one.
_debug_dwarf_hit(start: ulong, end: ulong, targets: Array<ulong>, hits: Array<bool>): bool {
    var any = false;
    ulong index = 0;
    while (index < targets.count) {
        var target = targets[index];
        if (target != 0 && target >= start && target < end) {
            hits[index] = true;
            any = true;
        }
        index = index + 1;
    }
    return any;
}

# Reads an attribute value of `form` (any but DW_FORM_string and
# DW_FORM_indirect): a number, an address, a reference or an offset. Blocks
# and expressions are skipped and read as 0, and so is an unknown form,
# which sets `cursor.failed` since its size is unknown.
_debug_dwarf_form(cursor: _DwarfCursor, form: ulong, unit: _DwarfUnit): ulong {
    if (form == 0x01) {
        return cursor.read_fixed(unit.address_size);
    } else if (form == 0x0b || form == 0x0c || form == 0x11) {
        return cursor.read_fixed(1);
    } else if (form == 0x05 || form == 0x12) {
        return cursor.read_fixed(2);
    } else if (form == 0x06 || form == 0x13) {
        return cursor.read_fixed(4);
    } else if (form == 0x07 || form == 0x14 || form == 0x20) {
        return cursor.read_fixed(8);
    } else if (form == 0x0f || form == 0x15) {
        return cursor.read_uleb();
    } else if (form == 0x0d) {
        return cursor.read_sleb() as ulong;
    } else if (form == 0x0e || form == 0x17) {
        return cursor.read_fixed(unit.offset_size);
    } else if (form == 0x10) {
        # DW_FORM_ref_addr: an address's size in DWARF 2, an offset's after.
        return cursor.read_fixed(unit.version == 2 ? unit.address_size : unit.offset_size);
    } else if (form == 0x19) {
        return 1;
    } else if (form == 0x0a) {
        cursor.skip(cursor.read_fixed(1));
    } else if (form == 0x03) {
        cursor.skip(cursor.read_fixed(2));
    } else if (form == 0x04) {
        cursor.skip(cursor.read_fixed(4));
    } else if (form == 0x09 || form == 0x18) {
        cursor.skip(cursor.read_uleb());
    } else {
        cursor.failed = true;
    }
    return 0;
}

# The NUL-terminated string at `offset` in `.debug_str`, or an empty String.
_debug_dwarf_string(sections: _DwarfSections, offset: ulong): String {
    if (offset >= sections.strings_size) {
        return String();
    }
    var cursor = _DwarfCursor(sections.strings, offset, sections.strings_size);
    var text = cursor.read_string();
    return cursor.failed ? String() : text;
}

# For each target, the inlined calls whose code covers it, outermost first:
# the `DW_TAG_inlined_subroutine` entries nested in the function
# (`DW_TAG_subprogram`) the address is in. Empty for an address outside
# inlined code.
_debug_dwarf_inline_chains(sections: _DwarfSections, targets: Array<ulong>): Array<Array<_DwarfInline>> {
    var chains = Array<Array<_DwarfInline>>();
    var hits = Array<bool>();
    for (var target in targets) {
        chains.append(Array<_DwarfInline>());
        hits.append(false);
    }
    var unit = _DwarfUnit();
    var die = _DwarfDie();
    # Names by DIE offset, as they are looked up.
    var names = _DwarfNames();
    ulong at = 0;
    while (at + 11 <= sections.info_size) {
        var readable = unit.read(sections, at);
        if (unit.end == 0) {
            break;
        }
        at = unit.end;
        if (!readable) {
            continue;
        }
        var cursor = _DwarfCursor(sections.info, unit.first, unit.end);
        ulong depth = 0;
        while (!cursor.failed && cursor.position < unit.end) {
            if (!die.read(cursor, unit, sections)) {
                if (cursor.failed || depth <= 1) {
                    break;
                }
                depth = depth - 1;
                continue;
            }
            if (die.children) {
                depth = depth + 1;
            }
            # DW_TAG_compile_unit, DW_TAG_partial_unit
            if (die.tag == 0x11 || die.tag == 0x3c) {
                unit.base = die.has_low ? die.low : 0;
                unit.line_offset = die.line_offset;
                unit.has_lines = die.has_lines;
            } else if (die.tag == 0x2e || die.tag == 0x1d) {
                # DW_TAG_subprogram, DW_TAG_inlined_subroutine
                if (!die.covers(unit, sections, targets, hits)) {
                    continue;
                }
                ulong index = 0;
                while (index < targets.count) {
                    if (hits[index]) {
                        if (die.tag == 0x2e) {
                            chains[index] = Array<_DwarfInline>();
                        } else {
                            var function = die.has_origin ? names.lookup(sections, die.origin) : die.name;
                            var file = unit.file_name(sections, die.call_file);
                            chains[index].append(
                                _DwarfInline(function, file, die.call_line as int, die.call_column as int)
                            );
                        }
                    }
                    index = index + 1;
                }
            }
        }
    }
    return chains;
}

# The names of DIEs looked up by offset, remembered: a backtrace names the
# same inlined functions over and over.
struct _DwarfNames {
    var _offsets: Array<ulong>;
    var _names: Array<String>;
    var _unit: _DwarfUnit;

    construct() {
        _offsets = Array<ulong>();
        _names = Array<String>();
        _unit = _DwarfUnit();
    }

    # The name of the DIE at section offset `offset`, following its
    # `DW_AT_abstract_origin` and `DW_AT_specification` to the DIE that
    # carries one; an empty String when none does.
    lookup(sections: _DwarfSections, offset: ulong): String {
        ulong index = 0;
        while (index < _offsets.count) {
            if (_offsets[index] == offset) {
                return _names[index];
            }
            index = index + 1;
        }
        var name = String();
        var die = _DwarfDie();
        var at = offset;
        # A chain of origins is short; the limit guards against a cycle.
        var steps = 0;
        while (steps < 8) {
            if (!_find_unit(sections, at)) {
                break;
            }
            var cursor = _DwarfCursor(sections.info, at, _unit.end);
            if (!die.read(cursor, _unit, sections)) {
                break;
            }
            if (!die.name.is_empty || !die.has_origin) {
                name = die.name;
                break;
            }
            at = die.origin;
            steps = steps + 1;
        }
        _offsets.append(offset);
        _names.append(name);
        return name;
    }

    # Points `_unit` at the unit containing section offset `at`.
    _find_unit(sections: _DwarfSections, at: ulong): bool {
        if (_unit.end != 0 && at >= _unit.first && at < _unit.end) {
            return true;
        }
        ulong offset = 0;
        while (offset + 11 <= sections.info_size) {
            var readable = _unit.read(sections, offset);
            if (_unit.end == 0) {
                return false;
            }
            if (at < _unit.end) {
                return readable && at >= _unit.first;
            }
            offset = _unit.end;
        }
        return false;
    }
}
