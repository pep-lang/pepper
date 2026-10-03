# Resolving return addresses on macOS: the executable's Mach-O symbol
# table (mapped in memory) names the function, the DWARF in the `.dSYM`
# bundle a `-g` build writes beside it gives the source position and the
# inlined calls, and `dladdr` names the frames in system libraries.

import "backtrace";
import "dwarf";

[Target(OS(Mac))]
extern int dladdr(void* address, void* info);
[Target(OS(Mac))]
extern void* _dyld_get_image_header(uint index);
[Target(OS(Mac))]
extern uint _dyld_image_count();
[Target(OS(Mac))]
extern int _NSGetExecutablePath(char* buffer, uint* size);
[Target(OS(Mac))]
extern int open(char* path, int flags, ...);
[Target(OS(Mac))]
extern int close(int fd);
[Target(OS(Mac))]
extern long lseek(int fd, long offset, int whence);
[Target(OS(Mac))]
extern void* mmap(void* address, ulong length, int protection, int flags, int descriptor, long offset);
[Target(OS(Mac))]
extern int munmap(void* address, ulong length);

[Target(OS(Mac))]
export _debug_sys_symbolize(frames: Array<StackFrame>): Array<StackFrame> {
    __ptr<u8> header = _debug_executable_header();
    # Dl_info { dli_fname, dli_fbase, dli_sname, dli_saddr }
    __ptr<ulong> info = _pep_malloc(32);
    var symbols = _DebugMachSymbols(header);
    var targets = Array<ulong>();
    for (var frame in frames) {
        ulong target = 0;
        # The call is one byte before the return address.
        var lookup = frame.address > 0 ? frame.address - 1 : 0;
        if (lookup != 0 && dladdr(unsafe_cast<__ptr<void>>(lookup), info) != 0) {
            if (info[1] == unsafe_cast<ulong>(header)) {
                target = lookup - symbols.slide;
                frame.function = symbols.function_at(target);
            } else if (info[2] != 0) {
                frame.function = String(unsafe_cast<__ptr<char>>(info[2]));
            }
        }
        targets.append(target);
    }
    _pep_free(info);
    return _debug_dsym_frames(targets, frames);
}

# The executable's Mach-O header: the loaded image whose file type is
# MH_EXECUTE.
[Target(OS(Mac))]
_debug_executable_header(): __ptr<u8> {
    var count = _dyld_image_count();
    uint index = 0;
    while (index < count) {
        __ptr<u8> header = _dyld_get_image_header(index);
        if (header != __null && _debug_read(header, 12, 4) == 2) {
            return header;
        }
        index = index + 1;
    }
    return __null;
}

# The symbol table of the main executable, read where dyld mapped its
# __LINKEDIT segment, and its slide: how far from its linked address dyld
# loaded it.
[Target(OS(Mac))]
struct _DebugMachSymbols {
    var slide: ulong;
    # The 1-based section number of __TEXT,__text, where functions are.
    var _text_section: ulong;
    var _symbols: __ptr<u8>;
    var _count: ulong;
    var _names: __ptr<u8>;
    var _names_size: ulong;

    construct(header: __ptr<u8>) {
        slide = 0;
        _text_section = 0;
        _symbols = __null;
        _count = 0;
        _names = __null;
        _names_size = 0;
        _read(header);
    }

    _read(header: __ptr<u8>) {
        # MH_MAGIC_64
        if (header == __null || _debug_read(header, 0, 4) != 0xfeedfacf) {
            return;
        }
        var commands = _debug_read(header, 16, 4);
        ulong command = 32;
        ulong linkedit_address = 0;
        ulong linkedit_offset = 0;
        var linkedit = false;
        ulong symbol_offset = 0;
        ulong names_offset = 0;
        var symtab = false;
        var text = false;
        ulong sections = 0;
        ulong index = 0;
        while (index < commands) {
            var kind = _debug_read(header, command, 4);
            var size = _debug_read(header, command + 4, 4);
            if (kind == 0x19) {
                # LC_SEGMENT_64: its section_64 headers (80 bytes each)
                # follow it, numbered from 1 across the whole file.
                var count = _debug_read(header, command + 64, 4);
                if (_debug_name_is(header + command + 8, "__TEXT")) {
                    slide = unsafe_cast<ulong>(header) - _debug_read(header, command + 24, 8);
                    text = true;
                    ulong section = 0;
                    while (section < count) {
                        if (_debug_name_is(header + command + 72 + section * 80, "__text")) {
                            _text_section = sections + section + 1;
                        }
                        section = section + 1;
                    }
                }
                sections = sections + count;
            }
            # LC_SEGMENT_64 named __LINKEDIT
            if (kind == 0x19 && _debug_name_is(header + command + 8, "__LINKEDIT")) {
                linkedit_address = _debug_read(header, command + 24, 8);
                linkedit_offset = _debug_read(header, command + 40, 8);
                linkedit = true;
            } else if (kind == 0x2) {
                # LC_SYMTAB { symoff, nsyms, stroff, strsize }
                symbol_offset = _debug_read(header, command + 8, 4);
                _count = _debug_read(header, command + 12, 4);
                names_offset = _debug_read(header, command + 16, 4);
                _names_size = _debug_read(header, command + 20, 4);
                symtab = true;
            }
            if (size == 0) {
                break;
            }
            command = command + size;
            index = index + 1;
        }
        if (!linkedit || !symtab || !text) {
            _count = 0;
            return;
        }
        var base = linkedit_address + slide - linkedit_offset;
        _symbols = unsafe_cast<__ptr<u8>>(base + symbol_offset);
        _names = unsafe_cast<__ptr<u8>>(base + names_offset);
    }

    # The readable name of the function containing `address` (an address
    # before the slide), or an empty String: the nearest symbol at or
    # below it, since Mach-O symbols carry no size.
    function_at(address: ulong): String {
        ulong best = 0;
        ulong best_name = 0;
        var found = false;
        ulong index = 0;
        while (index < _count) {
            # nlist_64 { n_strx, n_type, n_sect, n_desc, n_value }
            var entry = index * 16;
            var symbol_type = _symbols[entry + 4];
            var section = _symbols[entry + 5] as ulong;
            var value = _debug_read(_symbols, entry + 8, 8);
            # Not a debugging (stab) entry, and defined in a section (N_SECT).
            if ((symbol_type & 0xe0) == 0
                && (symbol_type & 0x0e) == 0x0e
                && value <= address
                && (!found || value > best)) {
                best = value;
                best_name = _debug_read(_symbols, entry, 4);
                found = true;
            }
            index = index + 1;
        }
        if (!found || best_name >= _names_size) {
            return "";
        }
        var name = String(unsafe_cast<__ptr<char>>(_names + best_name));
        # C symbols carry a leading underscore on Mach-O.
        if (name.starts_with("_")) {
            name = name.substr_bytes(1, name.size - 1);
        }
        return _debug_demangle(name);
    }
}

# Whether the 16-byte, NUL-padded Mach-O name at `field` is `name`.
[Target(OS(Mac))]
_debug_name_is(field: __ptr<u8>, name: String): bool {
    var bytes = name.c_str();
    ulong index = 0;
    while (index < 16) {
        var expected = index < name.size ? bytes[index] as u8 : 0 as u8;
        if (field[index] != expected) {
            return false;
        }
        if (expected == 0) {
            return true;
        }
        index = index + 1;
    }
    return true;
}

# Fills source positions and adds inlined calls from `<executable>.dSYM/
# Contents/Resources/DWARF/<name>`, when a `-g` build left one beside the
# executable; returns the frames.
[Target(OS(Mac))]
_debug_dsym_frames(targets: Array<ulong>, frames: Array<StackFrame>): Array<StackFrame> {
    __ptr<char> buffer = _pep_malloc(4096);
    __ptr<uint> size = _pep_malloc(4);
    size[0] = 4096;
    var executable = _NSGetExecutablePath(buffer, size) == 0 ? String(buffer) : String();
    _pep_free(size);
    _pep_free(buffer);
    if (executable.is_empty) {
        return frames;
    }
    var slash = executable.rfind("/");
    var name = slash >= 0 ?
        executable.substr_bytes((slash + 1) as ulong, executable.size - (slash + 1) as ulong) :
        executable;
    var path = $"{executable}.dSYM/Contents/Resources/DWARF/{name}";
    var fd = open(path.c_str(), 0);
    if (fd < 0) {
        return frames;
    }
    var length = lseek(fd, 0, 2);
    __ptr<u8> data = __null;
    if (length >= 32) {
        var mapped = mmap(__null, length as ulong, 1, 2, fd, 0);
        if (unsafe_cast<ulong>(mapped) != 0xffffffffffffffff) {
            data = mapped as __ptr<u8>;
        }
    }
    close(fd);
    if (data == __null) {
        return frames;
    }
    var file_size = length as ulong;
    var dwarf = _DwarfSections();
    if (_debug_read(data, 0, 4) == 0xfeedfacf) {
        var commands = _debug_read(data, 16, 4);
        ulong command = 32;
        ulong index = 0;
        while (index < commands && command + 72 <= file_size) {
            var kind = _debug_read(data, command, 4);
            var command_size = _debug_read(data, command + 4, 4);
            # LC_SEGMENT_64 named __DWARF: its section_64 headers follow it.
            if (kind == 0x19 && _debug_name_is(data + command + 8, "__DWARF")) {
                var sections = _debug_read(data, command + 64, 4);
                ulong section = 0;
                while (section < sections && command + 72 + (section + 1) * 80 <= file_size) {
                    var header = command + 72 + section * 80;
                    var bytes = _debug_read(data, header + 40, 8);
                    var offset = _debug_read(data, header + 48, 4);
                    if (offset + bytes <= file_size) {
                        # Mach-O spells `.debug_line` `__debug_line`.
                        if (_debug_name_is(data + header, "__debug_info")) {
                            dwarf.set(".debug_info", data + offset, bytes);
                        } else if (_debug_name_is(data + header, "__debug_abbrev")) {
                            dwarf.set(".debug_abbrev", data + offset, bytes);
                        } else if (_debug_name_is(data + header, "__debug_str")) {
                            dwarf.set(".debug_str", data + offset, bytes);
                        } else if (_debug_name_is(data + header, "__debug_ranges")) {
                            dwarf.set(".debug_ranges", data + offset, bytes);
                        } else if (_debug_name_is(data + header, "__debug_line")) {
                            dwarf.set(".debug_line", data + offset, bytes);
                        }
                    }
                    section = section + 1;
                }
            }
            if (command_size == 0) {
                break;
            }
            command = command + command_size;
            index = index + 1;
        }
    }
    var all = _debug_dwarf_frames(dwarf, targets, frames);
    munmap(data, file_size);
    return all;
}
