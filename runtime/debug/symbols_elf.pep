# Resolving return addresses on Linux: the executable's ELF symbol table
# names the function, its DWARF (in a `-g` build) the source position and
# the inlined calls, and `dladdr` the frames in shared libraries.

import "backtrace";
import "dwarf";

[Target(OS(Linux))]
extern int dladdr(void* address, void* info);
[Target(OS(Linux))]
extern ulong getauxval(ulong entry);
[Target(OS(Linux))]
extern int open(char* path, int flags, ...);
[Target(OS(Linux))]
extern int close(int fd);
[Target(OS(Linux))]
extern long lseek(int fd, long offset, int whence);
[Target(OS(Linux))]
extern void* mmap(void* address, ulong length, int protection, int flags, int descriptor, long offset);
[Target(OS(Linux))]
extern int munmap(void* address, ulong length);

# AT_ENTRY: the executable's entry point, an address inside it.
const _DEBUG_AT_ENTRY: ulong = 9;

[Target(OS(Linux))]
_debug_sys_symbolize(frames: Array<StackFrame>): Array<StackFrame> {
    # Dl_info { dli_fname, dli_fbase, dli_sname, dli_saddr }
    __ptr<ulong> info = _pep_malloc(32);
    ulong main_base = 0;
    if (dladdr(unsafe_cast<__ptr<void>>(getauxval(_DEBUG_AT_ENTRY)), info) != 0) {
        main_base = info[1];
    }
    var image = _DebugElf("/proc/self/exe");
    var targets = Array<ulong>();
    for (var frame in frames) {
        ulong target = 0;
        # A return address is the instruction after the call; the call
        # itself is one byte back.
        var lookup = frame.address > 0 ? frame.address - 1 : 0;
        if (lookup != 0 && dladdr(unsafe_cast<__ptr<void>>(lookup), info) != 0) {
            if (info[1] == main_base && image.valid) {
                target = lookup - main_base + image.first_address;
                frame.function = image.function_at(target);
            } else if (info[2] != 0) {
                frame.function = String(unsafe_cast<__ptr<char>>(info[2]));
            }
        }
        targets.append(target);
    }
    _pep_free(info);
    var all = image.valid ? _debug_dwarf_frames(image.debug, targets, frames) : frames;
    image.close();
    return all;
}

# An ELF64 file mapped read-only, with the parts the symbolizer reads.
[Target(OS(Linux))]
struct _DebugElf {
    var data: __ptr<u8>;
    var size: ulong;
    var valid: bool;
    # The lowest loaded address: where the image's load bias is measured from.
    var first_address: ulong;
    var symbols_offset: ulong;
    var symbols_size: ulong;
    var names_offset: ulong;
    var names_size: ulong;
    # The DWARF sections, inside `data`.
    var debug: _DwarfSections;

    construct(path: String) {
        data = __null;
        size = 0;
        valid = false;
        first_address = 0;
        symbols_offset = 0;
        symbols_size = 0;
        names_offset = 0;
        names_size = 0;
        debug = _DwarfSections();
        _open(path);
    }

    _open(path: String) {
        var fd = open(path.c_str(), 0);
        if (fd < 0) {
            return;
        }
        var length = lseek(fd, 0, 2);
        if (length >= 64) {
            var mapped = mmap(__null, length as ulong, 1, 2, fd, 0);
            if (unsafe_cast<ulong>(mapped) != 0xffffffffffffffff) {
                data = mapped as __ptr<u8>;
                size = length as ulong;
            }
        }
        close(fd);
        if (data != __null) {
            _parse();
        }
    }

    _parse() {
        if (data[0] != 0x7f || data[1] != 'E' || data[2] != 'L' || data[3] != 'F' || data[4] != 2) {
            return;
        }
        var program_headers = _debug_read(data, 0x20, 8);
        var section_headers = _debug_read(data, 0x28, 8);
        var program_count = _debug_read(data, 0x38, 2);
        var section_count = _debug_read(data, 0x3c, 2);
        var names_index = _debug_read(data, 0x3e, 2);
        if (program_headers + program_count * 56 > size || section_headers + section_count * 64 > size) {
            return;
        }
        var first = true;
        ulong index = 0;
        while (index < program_count) {
            var header = program_headers + index * 56;
            # PT_LOAD
            if (_debug_read(data, header, 4) == 1) {
                var address = _debug_read(data, header + 16, 8);
                if (first || address < first_address) {
                    first_address = address;
                    first = false;
                }
            }
            index = index + 1;
        }
        first_address = first_address & ~0xfff;
        if (names_index >= section_count) {
            return;
        }
        var section_names = _debug_read(data, section_headers + names_index * 64 + 24, 8);
        ulong dynamic_symbols = 0;
        ulong dynamic_size = 0;
        ulong dynamic_link = 0;
        index = 0;
        while (index < section_count) {
            var header = section_headers + index * 64;
            var section_type = _debug_read(data, header + 4, 4);
            var offset = _debug_read(data, header + 24, 8);
            var length = _debug_read(data, header + 32, 8);
            var link = _debug_read(data, header + 40, 4);
            if (offset + length <= size) {
                # SHT_SYMTAB, then SHT_DYNSYM as the fallback of a stripped file.
                if (section_type == 2) {
                    symbols_offset = offset;
                    symbols_size = length;
                    _set_names(section_headers, section_count, link);
                } else if (section_type == 11) {
                    dynamic_symbols = offset;
                    dynamic_size = length;
                    dynamic_link = link;
                } else if (section_type == 1 && (_debug_read(data, header + 8, 8) & 0x800) == 0) {
                    # A DWARF section, unless SHF_COMPRESSED, which is not
                    # read.
                    var name = section_names + _debug_read(data, header, 4);
                    if (_name_is(name, ".debug_info")) {
                        debug.set(".debug_info", data + offset, length);
                    } else if (_name_is(name, ".debug_abbrev")) {
                        debug.set(".debug_abbrev", data + offset, length);
                    } else if (_name_is(name, ".debug_str")) {
                        debug.set(".debug_str", data + offset, length);
                    } else if (_name_is(name, ".debug_ranges")) {
                        debug.set(".debug_ranges", data + offset, length);
                    } else if (_name_is(name, ".debug_line")) {
                        debug.set(".debug_line", data + offset, length);
                    }
                }
            }
            index = index + 1;
        }
        if (symbols_size == 0 && dynamic_size > 0) {
            symbols_offset = dynamic_symbols;
            symbols_size = dynamic_size;
            _set_names(section_headers, section_count, dynamic_link);
        }
        valid = true;
    }

    # Points the symbol names at section `link`, the symbol table's strings.
    _set_names(section_headers: ulong, section_count: ulong, link: ulong) {
        if (link >= section_count) {
            return;
        }
        var header = section_headers + link * 64;
        names_offset = _debug_read(data, header + 24, 8);
        names_size = _debug_read(data, header + 32, 8);
        if (names_offset + names_size > size) {
            names_size = 0;
        }
    }

    # Whether the NUL-terminated name at `offset` is `name`.
    _name_is(offset: ulong, name: String): bool {
        if (offset + name.size >= size) {
            return false;
        }
        var bytes = name.c_str();
        ulong index = 0;
        while (index < name.size) {
            if (data[offset + index] != bytes[index] as u8) {
                return false;
            }
            index = index + 1;
        }
        return data[offset + name.size] == 0;
    }

    # The readable name of the function containing `address` (an address as
    # the file lays it out), or an empty String.
    function_at(address: ulong): String {
        ulong best = 0;
        ulong best_name = 0;
        var found = false;
        ulong symbol = symbols_offset;
        while (symbol + 24 <= symbols_offset + symbols_size) {
            # Elf64_Sym { st_name, st_info, st_other, st_shndx, st_value, st_size }
            var symbol_type = data[symbol + 4] & 0xf;
            var section = _debug_read(data, symbol + 6, 2);
            var start = _debug_read(data, symbol + 8, 8);
            var length = _debug_read(data, symbol + 16, 8);
            # STT_FUNC, defined
            if (symbol_type == 2 && section != 0 && start <= address && (length == 0 || address < start + length)) {
                if (!found || start > best) {
                    best = start;
                    best_name = _debug_read(data, symbol, 4);
                    found = true;
                }
            }
            symbol = symbol + 24;
        }
        if (!found || best_name >= names_size) {
            return "";
        }
        var name = String(unsafe_cast<__ptr<char>>(data + names_offset + best_name));
        return _debug_demangle(name);
    }

    close() {
        if (data != __null) {
            munmap(data, size);
            data = __null;
        }
        valid = false;
    }
}
