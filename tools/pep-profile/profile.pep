# A recording, whichever profiler made it: the frames it saw and the stacks
# of frames it sampled, read from `perf script` text, a samply profile, the
# text macOS `sample` writes, or folded stacks; then each frame's names,
# and the stacks folded into the "collapsed" format flame graphs draw.

import [File, Path] from io;
import json;
import "symbols";

# A frame as the profiler recorded it.
export struct Frame {
    # The executable or library the frame's code is in: a path, or a file
    # name when the profiler gives only that; empty when unknown.
    var library: String;
    # The frame's address in `library`, as llvm-symbolizer reads it; 0 when
    # only `symbol` and `offset` are known.
    var address: ulong;
    # The profiler's own name for the function, or empty.
    var symbol: String;
    # How far into `symbol` the frame is (perf), when `has_offset`.
    var offset: ulong;
    var has_offset: bool;
    # Whether the frame called the one below it, so that its address is a
    # return address: the call is the byte before it.
    var caller: bool;
    # The names the frame shows as, outermost first: one per function, the
    # ones inlined into it included (see `Profile.symbolize`).
    var names: Array<String>;

    construct(library: String, address: ulong, symbol: String, offset: ulong, has_offset: bool, caller: bool) {
        this.library = library;
        this.address = address;
        this.symbol = symbol;
        this.offset = offset;
        this.has_offset = has_offset;
        this.caller = caller;
        this.names = Array<String>();
    }
}

# What a profiler recorded: the distinct frames, and each sampled stack
# with its weight.
export struct Profile {
    var frames: Array<Frame>;
    # Each sampled stack, as indexes into `frames`, innermost first.
    var stacks: Array<Array<ulong>>;
    var weights: Array<long>;
    # Whether addresses count from each library's image base (samply's
    # relative addresses), rather than being the library's own addresses.
    var relative: bool;
    # The program's own name for each library's code, from samply's
    # symbol file, by library path then address (see `read_samply`).
    var _index: HashMap<String, ulong>;

    construct() {
        this.frames = Array<Frame>();
        this.stacks = Array<Array<ulong>>();
        this.weights = Array<long>();
        this.relative = false;
        this._index = HashMap<String, ulong>();
    }

    # The index of the frame with these parts, added when it is new.
    frame(library: String, address: ulong, symbol: String, offset: ulong, has_offset: bool, caller: bool): ulong {
        var key = $"{library}\n{address}\n{symbol}\n{offset}\n{has_offset}\n{caller}";
        if (_index.contains(key)) {
            return _index[key];
        }
        var index = frames.count;
        frames.append(Frame(library, address, symbol, offset, has_offset, caller));
        _index[key] = index;
        return index;
    }

    # Records one sampled stack, innermost frame first.
    add(stack: Array<ulong>, weight: long) {
        if (!stack.is_empty) {
            stacks.append(stack);
            weights.append(weight);
        }
    }

    # The total weight of every sample.
    total(): long {
        long sum = 0;
        for (var weight in weights) {
            sum += weight;
        }
        return sum;
    }

    # Gives every frame its names. With a symbolizer, a frame in a library
    # that is on this machine is looked up in its debug info, which names
    # the functions inlined at its address too; any other frame takes the
    # profiler's name for it, demangled. With `lines`, each name ends with
    # the file and line it is at (`work (main.pep:14)`).
    symbolize(symbolizer: Symbolizer?, lines: bool) {
        if (symbolizer.is_value()) {
            var libraries = Array<String>();
            for (var frame in frames) {
                if (!frame.library.is_empty and !libraries.contains(frame.library)) {
                    libraries.append(frame.library);
                }
            }
            for (var library in libraries) {
                if (Path(library).is_file()) {
                    _symbolize_library(symbolizer.value(), library, lines);
                }
            }
        }
        for (var frame in frames) {
            if (frame.names.is_empty) {
                frame.names.append(_fallback_name(frame));
            }
        }
    }

    _symbolize_library(symbolizer: Symbolizer, library: String, lines: bool) {
        # perf names a frame by symbol and offset: find where each symbol
        # starts to give the frame its address.
        var symbols = Array<String>();
        for (var frame in frames) {
            if (frame.library == library
                and frame.has_offset
                and !frame.symbol.is_empty
                and !symbols.contains(frame.symbol)) {
                symbols.append(frame.symbol);
            }
        }
        var starts = HashMap<String, ulong>();
        if (!symbols.is_empty) {
            var found = symbolizer.starts(library, symbols);
            for (var index in 0..symbols.count) {
                starts[symbols[index]] = found[index];
            }
        }
        var members = Array<ulong>();
        var addresses = Array<ulong>();
        for (var index in 0..frames.count) {
            var frame = frames[index];
            if (frame.library != library) {
                continue;
            }
            ulong address = frame.address;
            if (frame.has_offset) {
                var start = starts.contains(frame.symbol) ? starts[frame.symbol] : 0;
                if (start == 0) {
                    continue;
                }
                address = start + frame.offset;
                if (frame.caller and address > 0) {
                    address -= 1;
                }
            }
            members.append(index);
            addresses.append(address);
        }
        var locations = symbolizer.locations(library, addresses, relative);
        for (var at in 0..members.count) {
            var frame = frames[members[at]];
            var found = locations[at];
            # llvm-symbolizer lists the innermost function first.
            var index = found.count;
            while (index > 0) {
                index -= 1;
                frame.names.append(name_of(found[index], lines));
            }
        }
    }

    # Every sampled stack as folded-stack text: one line per distinct
    # stack, its names from the outermost frame in, joined by `;`, then its
    # total weight; sorted, so the text is the same for the same samples.
    fold(): String {
        var weights_by_stack = HashMap<String, long>();
        for (var at in 0..stacks.count) {
            var parts = Array<String>();
            var stack = stacks[at];
            var index = stack.count;
            while (index > 0) {
                index -= 1;
                for (var name in frames[stack[index]].names) {
                    parts.append(name.replace(";", ":"));
                }
            }
            var key = ";".join(parts);
            weights_by_stack[key] = weights_by_stack[key] + weights[at];
        }
        var keys = Array<String>();
        for (var (key, weight) in weights_by_stack) {
            keys.append(key);
        }
        keys.sort((a, b) => a.compare(b));
        var out = StringBuilder();
        for (var key in keys) {
            out.append(key).append(" ").append(to_string(weights_by_stack[key])).append("\n");
        }
        return out.to_string();
    }
}

# The name a location shows as: its function, and with `lines` its file
# and line.
name_of(location: Location, lines: bool): String {
    if (!lines or location.line <= 0 or location.file.is_empty) {
        return location.function;
    }
    return $"{location.function} ({base_name(location.file)}:{location.line})";
}

# The name of a frame no debug info covers: the profiler's, demangled, or
# the library it is in.
_fallback_name(frame: Frame): String {
    if (!frame.symbol.is_empty and frame.symbol != "[unknown]") {
        return demangle(frame.symbol);
    }
    if (!frame.library.is_empty and frame.library != "[unknown]") {
        return $"[{base_name(frame.library)}]";
    }
    return "[unknown]";
}

# The last component of a path, either separator.
export base_name(path: String): String {
    var slash = path.rfind("/");
    var backslash = path.rfind("\\");
    var at = slash > backslash ? slash : backslash;
    return at < 0 ? path : path.substr_bytes((at + 1) as ulong, path.size - (at + 1) as ulong);
}

# Reads `perf script -F period,ip,sym,symoff,dso` output: samples separated
# by blank lines, each a header line and then one tab-indented line per
# frame, innermost first: `5598c6d7a1af main+0x3f (/path/to/program)`.
export read_perf_script(text: String): Profile {
    var profile = Profile();
    var stack = Array<ulong>();
    for (var line in text.lines()) {
        if (!line.starts_with("\t")) {
            profile.add(stack, 1);
            stack = Array<ulong>();
            continue;
        }
        var trimmed = line.trim();
        var space = trimmed.find(" ");
        if (space < 0) {
            continue;
        }
        var rest = trimmed.substr_bytes((space + 1) as ulong, trimmed.size - (space + 1) as ulong);
        var library = "";
        var open = rest.rfind(" (");
        if (open >= 0 and rest.ends_with(")")) {
            library = rest.substr_bytes((open + 2) as ulong, rest.size - (open + 3) as ulong);
            rest = rest.substr_bytes(0, open as ulong);
        }
        ulong offset = 0;
        var has_offset = false;
        var plus = rest.rfind("+0x");
        if (plus > 0) {
            var parsed = ulong.parse(rest.substr_bytes((plus + 3) as ulong, rest.size - (plus + 3) as ulong), 16);
            if (parsed.is_value()) {
                offset = parsed.value();
                has_offset = true;
                rest = rest.substr_bytes(0, plus as ulong);
            }
        }
        stack.append(profile.frame(library, 0, without_version(rest), offset, has_offset, !stack.is_empty));
    }
    profile.add(stack, 1);
    return profile;
}

# A C library symbol without the version perf adds to it:
# `__libc_start_main@@GLIBC_2.34` is `__libc_start_main`.
without_version(symbol: String): String {
    var at = symbol.find("@");
    if (at <= 0 or symbol.starts_with("_P")) {
        return symbol;
    }
    var version = symbol.substr_bytes(at as ulong, symbol.size - at as ulong).replace("@", "");
    if (version.is_empty or !version.byte_at(0).is_upper()) {
        return symbol;
    }
    return symbol.substr_bytes(0, at as ulong);
}

# Reads a profile samply saved (`samply record --save-only`), in the Firefox
# Profiler's format: per thread, a stack table whose entries each name a
# frame and the entry for its caller, and each sample's stack entry.
# `symbols` is samply's `.syms.json` file beside it, or `Null`: it names
# each library's functions by address, for frames no debug info on this
# machine covers. Without `idle`, a sample whose thread used no CPU since
# the last one (`threadCPUDelta` 0) is left out: samply records a waiting
# thread too, as one sample weighted by how long it waited, and a thread
# pool's idle worker would otherwise fill half the graph.
export read_samply(document: json.JsonValue, symbols: json.JsonValue, idle: bool): Result<Profile> {
    var profile = Profile();
    profile.relative = true;
    var libraries = document["libs"].as_array();
    var threads = document["threads"].as_array();
    if (libraries.is_empty() or threads.is_empty()) {
        return Result<Profile>.Err("not a samply profile: no 'libs' or 'threads'");
    }
    var tables = Array<SymbolTable>();
    for (var library in libraries.value()) {
        tables.append(SymbolTable(symbols, library["debugName"].as_string()));
    }
    for (var thread in threads.value()) {
        var strings = thread["stringArray"];
        var samples = thread["samples"];
        var stack_table = thread["stackTable"];
        var frame_table = thread["frameTable"];
        var func_table = thread["funcTable"];
        var resource_table = thread["resourceTable"];
        # Each stack entry's frames, innermost first, made once.
        var made = HashMap<long, Array<ulong>>();
        var count = samples["length"].as_int();
        if (count.is_empty()) {
            continue;
        }
        for (var sample in 0..(count.value() as ulong)) {
            var entry = samples["stack"][sample].as_int();
            if (entry.is_empty()) {
                continue;
            }
            var weight = samples["weight"][sample].as_int();
            var cpu = samples["threadCPUDelta"][sample].as_int();
            if (!idle and cpu.is_value() and cpu.value() == 0) {
                continue;
            }
            if (!made.contains(entry.value())) {
                var stack = Array<ulong>();
                var at = entry;
                while (at.is_value()) {
                    var frame = stack_table["frame"][at.value() as ulong].as_int().value() as ulong;
                    var address = frame_table["address"][frame].as_int();
                    var function = frame_table["func"][frame].as_int().value() as ulong;
                    var resource = func_table["resource"][function].as_int();
                    var library = "";
                    var symbol = "";
                    if (resource.is_value() and resource.value() >= 0) {
                        var index = resource_table["lib"][resource.value() as ulong].as_int();
                        if (index.is_value()
                            and index.value() >= 0
                            and index.value() < libraries.value().count as long) {
                            var described = libraries.value()[index.value() as ulong];
                            var path = described["path"].as_string();
                            library = path.is_value() ? path.value() : "";
                            if (address.is_value() and address.value() >= 0) {
                                symbol = tables[index.value() as ulong].name_at(address.value() as ulong);
                            }
                        }
                    }
                    if (symbol.is_empty) {
                        var name = strings[func_table["name"][function].as_int().value() as ulong].as_string();
                        symbol = name.is_value() and !name.value().starts_with("0x") ? name.value() : "";
                    }
                    var known = address.is_value() and address.value() >= 0;
                    # samply's addresses for callers already point into the call.
                    stack.append(profile.frame(library, known ? address.value() as ulong : 0, symbol, 0, false, false));
                    at = stack_table["prefix"][at.value() as ulong].as_int();
                }
                made[entry.value()] = stack;
            }
            profile.add(made[entry.value()], weight.is_value() ? weight.value() : 1);
        }
    }
    return Result<Profile>.Ok(profile);
}

# One library's functions from samply's `.syms.json`, sorted by address.
struct SymbolTable {
    var starts: Array<ulong>;
    var ends: Array<ulong>;
    var names: Array<String>;

    construct(symbols: json.JsonValue, debug_name: String?) {
        this.starts = Array<ulong>();
        this.ends = Array<ulong>();
        this.names = Array<String>();
        _load(symbols, debug_name);
    }

    _load(symbols: json.JsonValue, debug_name: String?) {
        var data = symbols["data"].as_array();
        if (data.is_empty() or debug_name.is_empty()) {
            return;
        }
        var strings = symbols["string_table"];
        for (var library in data.value()) {
            if (library["debug_name"].as_string() != debug_name) {
                continue;
            }
            var table = library["symbol_table"].as_array();
            if (table.is_empty()) {
                return;
            }
            for (var entry in table.value()) {
                var start = entry["rva"].as_int();
                var size = entry["size"].as_int();
                if (start.is_empty() or size.is_empty()) {
                    continue;
                }
                # The outermost function the debug info gives is the one
                # the symbol is; samply's symbol names lose a leading `_`.
                var named = entry["symbol"].as_int();
                var frames = entry["frames"].as_array();
                if (frames.is_value() and !frames.value().is_empty) {
                    named = frames.value()[frames.value().count - 1]["function"].as_int();
                }
                var name = named.is_value() ? strings[named.value() as ulong].as_string() : Optional<String>.Empty;
                if (name.is_value()) {
                    starts.append(start.value() as ulong);
                    ends.append((start.value() + size.value()) as ulong);
                    names.append(name.value());
                }
            }
            return;
        }
    }

    # The name of the function at `address`, or empty.
    name_at(address: ulong): String {
        ulong low = 0;
        ulong high = starts.count;
        while (low < high) {
            var middle = (low + high) / 2;
            if (starts[middle] <= address) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        if (low == 0 or address >= ends[low - 1]) {
            return "";
        }
        return names[low - 1];
    }
}

# Reads the report macOS `sample` writes: its "Call graph:" section is a
# tree, one line per function, indented by depth, each with the number of
# samples taken in it and everything it called:
# `    + 2341 main  (in program) + 175  [0x100003f2f]  main.pep:26`.
export read_sample_report(text: String): Profile {
    var profile = Profile();
    var path = Array<ulong>();     # the frames from the root to here
    var counts = Array<long>();    # each one's samples
    var children = Array<long>();  # the samples its children took
    var in_graph = false;
    for (var line in text.lines()) {
        if (!in_graph) {
            in_graph = line.starts_with("Call graph:");
            continue;
        }
        if (line.trim().is_empty or !line.starts_with(" ")) {
            break;
        }
        # The count starts after the indentation and the tree's marks.
        ulong column = 0;
        while (column < line.size and !line.byte_at(column).is_digit()) {
            column += 1;
        }
        var space = line.find(" ", column);
        if (column >= line.size or space < 0) {
            continue;
        }
        var count = long.parse(line.substr_bytes(column, space as ulong - column));
        if (count.is_empty()) {
            continue;
        }
        var depth = column >= 4 ? (column - 4) / 2 : 0;
        var rest = line.substr_bytes((space + 1) as ulong, line.size - (space + 1) as ulong);
        var library = "";
        var open = rest.find("  (in ");
        var symbol = rest;
        if (open >= 0) {
            symbol = rest.substr_bytes(0, open as ulong);
            var close = rest.find(")", open as ulong);
            if (close > open) {
                library = rest.substr_bytes((open + 6) as ulong, (close - open - 6) as ulong);
            }
        }
        # Leaving deeper frames: each keeps the samples its children did not.
        while (path.count > depth) {
            _close_sample_frame(profile, path, counts, children);
        }
        if (depth == 0) {
            # A thread: not a frame of its own.
            path.append(profile.frame("", 0, "", 0, false, false));
            counts.append(0);
            children.append(0);
            continue;
        }
        if (!children.is_empty) {
            children[children.count - 1] = children[children.count - 1] + count.value();
        }
        path.append(profile.frame(library, 0, symbol.trim(), 0, false, false));
        counts.append(count.value());
        children.append(0);
    }
    while (!path.is_empty) {
        _close_sample_frame(profile, path, counts, children);
    }
    return profile;
}

# Ends the innermost open frame of a `sample` call tree, recording the
# samples taken in it that its children do not account for.
_close_sample_frame(profile: Profile, path: Array<ulong>, counts: Array<long>, children: Array<long>) {
    var own = counts.pop() - children.pop();
    if (own > 0 and path.count > 1) {
        var stack = Array<ulong>();
        var index = path.count;
        while (index > 1) {
            index -= 1;
            stack.append(path[index]);
        }
        profile.add(stack, own);
    }
    path.pop();
}
