# The compressor: LZ77 over a 32 KiB window with hash chains, then each
# block written stored, with the fixed codes, or with codes built for it,
# whichever is smallest (RFC 1951), inside zlib or gzip framing.

import "checksum";
import "format";
import "inflate";

# The most matches one block holds before it is written.
const _DEFLATE_BLOCK_TOKENS: ulong = 16384;
# The input a match search may look at past its start: the longest match
# plus the three bytes the hash reads.
const _DEFLATE_LOOKAHEAD: ulong = 262;
const _DEFLATE_WINDOW: ulong = 32768;
const _DEFLATE_HASH_SIZE: ulong = 32768;
# A token with this bit set is a match: length << 16 | distance.
const _DEFLATE_MATCH: uint = 0x80000000;

# Compresses one stream of a `Format`. `write` and `finish` append the
# compressed bytes to `output`, which the caller empties as it likes.
export struct _Deflater {
    var _format: Format;
    var _level: int;
    # The match search's effort, as zlib's table has it: how many earlier
    # positions to try, the length that is good enough to stop at, the
    # length after which a search tries only a quarter of the chain, and
    # whether to look one byte further for a longer match before taking
    # one. With `_lazy`, `_max_lazy` is the match length not worth looking
    # past; without it, the longest match whose positions still go into
    # the hash chains.
    var _max_chain: ulong;
    var _nice_length: ulong;
    var _good_length: ulong;
    var _max_lazy: ulong;
    var _lazy: bool;

    # The input from absolute stream position `_base` on.
    var _buffer: u8[];
    var _base: ulong;
    # The absolute position of the first byte not turned into tokens yet,
    # and of the first byte of the block being collected.
    var _done: ulong;
    var _block_start: ulong;
    # Hash chains: the latest position whose three bytes hash to each
    # value, and for each position in the window the position before it
    # with the same hash. Positions are stored plus one, modulo 2^32 (0 for
    # none), which halves the tables; a search only follows a chain while
    # the distances grow and stay in the window, and checks every byte it
    # matches, so a stale entry can cost a match but never make a wrong one.
    var _head: uint[];
    var _prev: uint[];
    var _inserted: ulong;
    # Lazy matching: whether the byte before `_done` is still to be
    # written, and the match found there (length 0 for none).
    var _match_available: bool;
    var _prev_length: ulong;
    var _prev_distance: ulong;

    var _tokens: uint[];
    var _literal_counts: uint[];
    var _distance_counts: uint[];
    # The length code (0 through 28) of each match length 3 through 258,
    # and the distance code of each distance 1 through 32768, through
    # `_distance_code`.
    var _length_codes: u8[];
    var _distance_codes: u8[];
    var _length_base: uint[];
    var _length_extra: uint[];
    var _distance_base: uint[];
    var _distance_extra: uint[];

    var output: u8[];
    var _bits: ulong;
    var _bit_count: ulong;

    var _started: bool;
    # The Adler-32 of the preset dictionary, when one was given.
    var _has_dictionary: bool;
    var _dictionary_id: uint;
    var _crc: Crc32;
    var _adler: Adler32;
    var _size: uint;

    construct(format: Format, level: int) {
        _format = format;
        _level = level;
        # zlib's configuration table (deflate.c).
        var goods = [0, 4, 4, 4, 4, 8, 8, 8, 32, 32];
        var lazies = [0, 4, 5, 6, 4, 16, 16, 32, 128, 258];
        var nices = [0, 8, 16, 32, 16, 32, 128, 128, 258, 258];
        var chains = [0, 4, 8, 32, 16, 32, 128, 256, 1024, 4096];
        _good_length = goods[level as ulong] as ulong;
        _max_lazy = lazies[level as ulong] as ulong;
        _nice_length = nices[level as ulong] as ulong;
        _max_chain = chains[level as ulong] as ulong;
        _lazy = level >= 4;
        _buffer = Array<u8>();
        _head = Array<uint>(_DEFLATE_HASH_SIZE);
        _prev = Array<uint>(_DEFLATE_WINDOW);
        ulong index = 0;
        while (index < _DEFLATE_WINDOW) {
            _head.append(0);
            _prev.append(0);
            index += 1;
        }
        _tokens = Array<uint>(_DEFLATE_BLOCK_TOKENS);
        _literal_counts = Array<uint>(286);
        _distance_counts = Array<uint>(30);
        _clear_counts();
        _length_base = [
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            13,
            15,
            17,
            19,
            23,
            27,
            31,
            35,
            43,
            51,
            59,
            67,
            83,
            99,
            115,
            131,
            163,
            195,
            227,
            258
        ];
        _length_extra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
        _distance_base = [
            1,
            2,
            3,
            4,
            5,
            7,
            9,
            13,
            17,
            25,
            33,
            49,
            65,
            97,
            129,
            193,
            257,
            385,
            513,
            769,
            1025,
            1537,
            2049,
            3073,
            4097,
            6145,
            8193,
            12289,
            16385,
            24577
        ];
        _distance_extra = [
            0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
        ];
        _length_codes = Array<u8>(259);
        ulong length = 0;
        ulong code = 0;
        while (length < 259) {
            while (code + 1 < 29 && length >= (_length_base[code + 1] as ulong)) {
                code += 1;
            }
            _length_codes.append(code as u8);
            length += 1;
        }
        # Distances up to 256 by `distance - 1`; longer ones by
        # `256 + (distance - 1) >> 7`.
        _distance_codes = Array<u8>(512);
        index = 0;
        code = 0;
        while (index < 512) {
            ulong distance = 0;
            if (index < 256) {
                distance = index + 1;
            } else {
                distance = ((index - 256) << 7) + 1;
            }
            while (code + 1 < 30 && distance >= (_distance_base[code + 1] as ulong)) {
                code += 1;
            }
            _distance_codes.append(code as u8);
            index += 1;
        }
        output = Array<u8>();
        _crc = Crc32();
        _adler = Adler32();
    }

    _distance_code(distance: ulong): ulong {
        __ptr<u8> codes = _distance_codes._data;
        if (distance <= 256) {
            return codes[distance - 1] as ulong;
        }
        return codes[256 + ((distance - 1) >> 7)] as ulong;
    }

    _clear_counts() {
        _literal_counts.clear();
        _distance_counts.clear();
        var index = 0;
        while (index < 286) {
            _literal_counts.append(0);
            index += 1;
        }
        index = 0;
        while (index < 30) {
            _distance_counts.append(0);
            index += 1;
        }
    }

    # Starts the window with the last 32 KiB of `dictionary`, so the first
    # bytes written can refer back into it; a zlib header names it by its
    # Adler-32. Called before the first `write`.
    set_dictionary(dictionary: u8[]) {
        _has_dictionary = true;
        _dictionary_id = Adler32.of(dictionary);
        var start = dictionary.count > _DEFLATE_WINDOW ? dictionary.count - _DEFLATE_WINDOW : 0;
        _buffer._append_raw(dictionary._data + start, dictionary.count - start);
        # Its positions join the hash chains at the first search
        # (`_inserted` is still 0), but no token covers them.
        _done = _buffer.count;
        _block_start = _done;
    }

    # Adds `data` to the stream, writing whatever blocks it completes.
    write(data: u8[]) {
        _start();
        if (_format == Format.Gzip) {
            _crc.update(data);
            _size += data.count as uint;
        } else if (_format == Format.Zlib) {
            _adler.update(data);
        }
        _buffer.append_all(data);
        _compress(false);
    }

    # Writes the rest of the stream and its trailer.
    finish() {
        _start();
        _compress(true);
        _flush_bits();
        if (_format == Format.Gzip) {
            _write_little_endian(_crc.value as ulong, 4);
            _write_little_endian(_size as ulong, 4);
        } else if (_format == Format.Zlib) {
            var value = _adler.value;
            output.append((value >> 24) as u8);
            output.append(((value >> 16) & 255) as u8);
            output.append(((value >> 8) & 255) as u8);
            output.append((value & 255) as u8);
        }
    }

    # Writes the zlib or gzip header, once.
    _start() {
        if (_started) {
            return;
        }
        _started = true;
        if (_format == Format.Zlib) {
            # A 32 KiB window, deflate, and the level class.
            uint level_class = 2;
            if (_level <= 1) {
                level_class = 0;
            } else if (_level <= 5) {
                level_class = 1;
            } else if (_level >= 7) {
                level_class = 3;
            }
            uint flags = level_class << 6;
            if (_has_dictionary) {
                flags = flags | 32;
            }
            flags += 31 - ((120 * 256 + flags) % 31);
            output.append(120);
            output.append(flags as u8);
            if (_has_dictionary) {
                output.append((_dictionary_id >> 24) as u8);
                output.append(((_dictionary_id >> 16) & 255) as u8);
                output.append(((_dictionary_id >> 8) & 255) as u8);
                output.append((_dictionary_id & 255) as u8);
            }
        } else if (_format == Format.Gzip) {
            # Magic, deflate, no flags, no modification time.
            output.append(31);
            output.append(139);
            output.append(8);
            output.append(0);
            _write_little_endian(0, 4);
            # Extra flags: 2 for the slowest level, 4 for the fastest.
            if (_level == 9) {
                output.append(2);
            } else if (_level == 1) {
                output.append(4);
            } else {
                output.append(0);
            }
            # Operating system: unknown.
            output.append(255);
        }
    }

    _write_little_endian(value: ulong, count: ulong) {
        ulong index = 0;
        while (index < count) {
            output.append(((value >> (index * 8)) & 255) as u8);
            index += 1;
        }
    }

    _write_bits(value: ulong, count: ulong) {
        _bits = _bits | (value << _bit_count);
        _bit_count += count;
        while (_bit_count >= 8) {
            output.append((_bits & 255) as u8);
            _bits = _bits >> 8;
            _bit_count -= 8;
        }
    }

    # Pads the bits written to a whole byte.
    _flush_bits() {
        if (_bit_count > 0) {
            output.append((_bits & 255) as u8);
        }
        _bits = 0;
        _bit_count = 0;
    }

    # Turns the buffered input into tokens and blocks. Without `final`,
    # keeps the last `_DEFLATE_LOOKAHEAD` bytes for the matches that start
    # before them.
    _compress(final: bool) {
        var end = _base + _buffer.count;
        if (_level == 0) {
            _compress_stored(final, end);
            _trim();
            return;
        }
        var limit = end;
        if (!final) {
            if (end < _done + _DEFLATE_LOOKAHEAD) {
                return;
            }
            limit = end - _DEFLATE_LOOKAHEAD;
        }
        if (_lazy) {
            _compress_lazy(limit, end);
        } else {
            _compress_fast(limit, end);
        }
        if (final) {
            # A match found at the last position would reach past the end,
            # so what waits is a literal.
            if (_match_available) {
                _emit_literal(_buffer._data[_done - 1 - _base]);
                _match_available = false;
            }
            _write_block(true, end);
        }
        _trim();
    }

    # Levels 1 to 3 (zlib's `deflate_fast`): takes the longest match at each
    # position, and leaves the positions inside a match longer than
    # `_max_lazy` out of the hash chains.
    _compress_fast(limit: ulong, end: ulong) {
        __ptr<u8> data = _buffer._data;
        var position = _done;
        while (position < limit) {
            var found = _find(position, end, _max_chain, 2);
            var length = found >> 16;
            if (length >= 3) {
                _emit_match(length, found & 65535);
                position += length;
                if (length > _max_lazy) {
                    _inserted = position;
                }
            } else {
                _emit_literal(data[position - _base]);
                position += 1;
            }
            if (_tokens.count >= _DEFLATE_BLOCK_TOKENS && position < end) {
                _write_block(false, position);
            }
        }
        _done = position;
    }

    # Levels 4 to 9 (zlib's `deflate_slow`): before taking a match, looks
    # for a longer one at the next position, and takes that one instead
    # (writing a literal) when it finds it.
    _compress_lazy(limit: ulong, end: ulong) {
        __ptr<u8> data = _buffer._data;
        var position = _done;
        while (position < limit) {
            var previous_length = _prev_length;
            ulong length = 0;
            ulong distance = 0;
            if (previous_length < _max_lazy) {
                var chain = _max_chain;
                if (previous_length >= _good_length) {
                    chain = chain >> 2;
                }
                var best = previous_length;
                if (best < 2) {
                    best = 2;
                }
                var found = _find(position, end, chain, best);
                length = found >> 16;
                distance = found & 65535;
                # A short match far back costs about as much as its literals.
                if (length == 3 && distance > 4096) {
                    length = 0;
                }
            }
            if (previous_length >= 3 && length <= previous_length) {
                _emit_match(previous_length, _prev_distance);
                position = position - 1 + previous_length;
                _match_available = false;
                _prev_length = 0;
            } else {
                if (_match_available) {
                    _emit_literal(data[position - 1 - _base]);
                }
                _match_available = true;
                _prev_length = length;
                _prev_distance = distance;
                position += 1;
            }
            if (_tokens.count >= _DEFLATE_BLOCK_TOKENS && position < end) {
                var block_end = position;
                if (_match_available) {
                    block_end -= 1;
                }
                _write_block(false, block_end);
            }
        }
        _done = position;
    }

    _emit_literal(byte: u8) {
        _tokens.append(byte as uint);
        __ptr<uint> counts = _literal_counts._data;
        counts[byte as ulong] += 1;
    }

    _emit_match(length: ulong, distance: ulong) {
        _tokens.append(_DEFLATE_MATCH | ((length as uint) << 16) | (distance as uint));
        __ptr<uint> literal_counts = _literal_counts._data;
        __ptr<uint> distance_counts = _distance_counts._data;
        __ptr<u8> length_codes = _length_codes._data;
        literal_counts[257 + (length_codes[length] as ulong)] += 1;
        distance_counts[_distance_code(distance)] += 1;
    }

    # Level 0: stored blocks only, of at most 65535 bytes each.
    _compress_stored(final: bool, end: ulong) {
        while (end - _done > 65535 || (!final && end - _done == 65535)) {
            _write_stored(_done, 65535, false);
            _done += 65535;
        }
        if (final) {
            _write_stored(_done, end - _done, true);
            _done = end;
        }
        _block_start = _done;
    }

    # Drops input that no block or match needs any more.
    _trim() {
        ulong keep = 0;
        if (_done > _DEFLATE_WINDOW) {
            keep = _done - _DEFLATE_WINDOW;
        }
        if (_block_start < keep) {
            keep = _block_start;
        }
        if (keep < _base || keep - _base < 65536) {
            return;
        }
        var drop = keep - _base;
        var kept = Array<u8>(_buffer.count - drop + 131072);
        kept._append_raw(_buffer._data + drop, _buffer.count - drop);
        _buffer = kept;
        _base = keep;
    }

    _hash(data: __ptr<u8>, at: ulong): ulong {
        var value = (data[at] as uint) | ((data[at + 1] as uint) << 8) | ((data[at + 2] as uint) << 16);
        return (value.wrapping_mul(2654435761) >> 17) as ulong;
    }

    # Adds the positions before `position` to the hash chains, finds the
    # longest match at `position` that is longer than `best` (at least 2),
    # trying at most `chain` earlier positions, then adds `position` itself.
    # Returns `length << 16 | distance`, or 0 for none.
    _find(position: ulong, end: ulong, chain: ulong, best: ulong): ulong {
        __ptr<u8> data = _buffer._data;
        __ptr<uint> head = _head._data;
        __ptr<uint> prev = _prev._data;
        while (_inserted < position) {
            _insert(data, head, prev, _inserted, end);
            _inserted += 1;
        }
        ulong found = 0;
        var max_length = end - position;
        if (max_length > 258) {
            max_length = 258;
        }
        if (max_length > best) {
            var here = position - _base;
            __ptr<u8> scan = data + here;
            var current = ((position + 1) & 0xFFFFFFFF) as uint;
            var candidate = head[_hash(data, here)];
            var nice = _nice_length;
            var reach = here;
            if (reach > _DEFLATE_WINDOW) {
                reach = _DEFLATE_WINDOW;
            }
            var tries = chain;
            ulong last = 0;
            while (candidate != 0 && tries > 0) {
                var distance = current.wrapping_sub(candidate) as ulong;
                if (distance <= last || distance > reach) {
                    break;
                }
                last = distance;
                __ptr<u8> earlier = data + (here - distance);
                # The two bytes at the end of the best match so far, then
                # the first two: most candidates fail one of these.
                if (earlier[best] == scan[best]
                    && earlier[best - 1] == scan[best - 1]
                    && earlier[0] == scan[0]
                    && earlier[1] == scan[1]) {
                    var length = _compress_match_length(earlier, scan, max_length);
                    if (length > best) {
                        best = length;
                        found = (length << 16) | distance;
                        if (length >= nice || length == max_length) {
                            break;
                        }
                    }
                }
                candidate = prev[(position - distance) & (_DEFLATE_WINDOW - 1)];
                tries -= 1;
            }
        }
        if (_inserted == position) {
            _insert(data, head, prev, position, end);
            _inserted += 1;
        }
        return found;
    }

    _insert(data: __ptr<u8>, head: __ptr<uint>, prev: __ptr<uint>, position: ulong, end: ulong) {
        if (position + 3 > end) {
            return;
        }
        var hash = _hash(data, position - _base);
        prev[position & (_DEFLATE_WINDOW - 1)] = head[hash];
        head[hash] = ((position + 1) & 0xFFFFFFFF) as uint;
    }

    # Writes the tokens collected as one block covering the input from
    # `_block_start` to `end`, in whichever form is smallest.
    _write_block(final: bool, end: ulong) {
        _literal_counts[256] += 1;
        var literal_lengths = _compress_code_lengths(_literal_counts, 286, 15);
        var distance_lengths = _compress_code_lengths(_distance_counts, 30, 15);
        ulong literal_count = 286;
        while (literal_count > 257 && literal_lengths[literal_count - 1] == 0) {
            literal_count -= 1;
        }
        ulong distance_count = 30;
        while (distance_count > 1 && distance_lengths[distance_count - 1] == 0) {
            distance_count -= 1;
        }
        # The code lengths, run-length encoded (RFC 1951 section 3.2.7):
        # each entry is symbol | extra bits << 8.
        var all_lengths = Array<u8>(literal_count + distance_count);
        ulong index = 0;
        while (index < literal_count) {
            all_lengths.append(literal_lengths[index]);
            index += 1;
        }
        index = 0;
        while (index < distance_count) {
            all_lengths.append(distance_lengths[index]);
            index += 1;
        }
        var runs = _compress_length_runs(all_lengths);
        var run_counts = Array<uint>(19);
        index = 0;
        while (index < 19) {
            run_counts.append(0);
            index += 1;
        }
        for (var run in runs) {
            run_counts[(run & 255) as ulong] += 1;
        }
        var run_lengths = _compress_code_lengths(run_counts, 19, 7);
        var order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
        ulong order_count = 19;
        while (order_count > 4 && run_lengths[order[order_count - 1] as ulong] == 0) {
            order_count -= 1;
        }

        # The size of each form, in bits.
        ulong dynamic_bits = 3 + 14 + 3 * order_count;
        for (var run in runs) {
            var symbol = (run & 255) as ulong;
            dynamic_bits += run_lengths[symbol] as ulong;
            if (symbol == 16) {
                dynamic_bits += 2;
            } else if (symbol == 17) {
                dynamic_bits += 3;
            } else if (symbol == 18) {
                dynamic_bits += 7;
            }
        }
        ulong fixed_bits = 3;
        ulong extra_bits = 0;
        index = 0;
        while (index < 286) {
            var count = _literal_counts[index] as ulong;
            if (count != 0) {
                dynamic_bits += count * (literal_lengths[index] as ulong);
                fixed_bits += count * _compress_fixed_length(index);
                if (index > 256) {
                    extra_bits += count * (_length_extra[index - 257] as ulong);
                }
            }
            index += 1;
        }
        index = 0;
        while (index < 30) {
            var count = _distance_counts[index] as ulong;
            if (count != 0) {
                dynamic_bits += count * (distance_lengths[index] as ulong);
                fixed_bits += count * 5;
                extra_bits += count * (_distance_extra[index] as ulong);
            }
            index += 1;
        }
        dynamic_bits += extra_bits;
        fixed_bits += extra_bits;
        var input_size = end - _block_start;
        var pieces = (input_size + 65534) / 65535;
        if (pieces == 0) {
            pieces = 1;
        }
        var stored_bits = (input_size + pieces * 5) * 8 + 7;

        if (stored_bits <= dynamic_bits && stored_bits <= fixed_bits) {
            var start = _block_start;
            while (end - start > 65535) {
                _write_stored(start, 65535, false);
                start += 65535;
            }
            _write_stored(start, end - start, final);
        } else if (fixed_bits <= dynamic_bits) {
            _write_bits(_compress_flag(final), 1);
            _write_bits(1, 2);
            var fixed_literals = Array<u8>(288);
            index = 0;
            while (index < 288) {
                fixed_literals.append(_compress_fixed_length(index) as u8);
                index += 1;
            }
            var fixed_distances = Array<u8>(30);
            index = 0;
            while (index < 30) {
                fixed_distances.append(5);
                index += 1;
            }
            _write_tokens(fixed_literals, fixed_distances);
        } else {
            _write_bits(_compress_flag(final), 1);
            _write_bits(2, 2);
            _write_bits(literal_count - 257, 5);
            _write_bits(distance_count - 1, 5);
            _write_bits(order_count - 4, 4);
            index = 0;
            while (index < order_count) {
                _write_bits(run_lengths[order[index] as ulong] as ulong, 3);
                index += 1;
            }
            var run_codes = _compress_canonical_codes(run_lengths);
            for (var run in runs) {
                var symbol = (run & 255) as ulong;
                _write_bits(run_codes[symbol] as ulong, run_lengths[symbol] as ulong);
                var extra = (run >> 8) as ulong;
                if (symbol == 16) {
                    _write_bits(extra, 2);
                } else if (symbol == 17) {
                    _write_bits(extra, 3);
                } else if (symbol == 18) {
                    _write_bits(extra, 7);
                }
            }
            _write_tokens(literal_lengths, distance_lengths);
        }
        _tokens.clear();
        _clear_counts();
        _block_start = end;
    }

    # Writes the block's tokens and its end code with the given codes.
    _write_tokens(literal_lengths: u8[], distance_lengths: u8[]) {
        var literal_codes = _compress_canonical_codes(literal_lengths);
        var distance_codes = _compress_canonical_codes(distance_lengths);
        # A token takes at most 48 bits, and each one leaves fewer than 8
        # bits in `bits`; the 8 bytes stored after each token may run up to
        # 7 bytes past the ones it fills.
        var token_count = _tokens.count;
        output.reserve(output.count + token_count * 6 + 16);
        __ptr<u8> out = output._data;
        var at = output.count;
        var bits = _bits;
        var count = _bit_count;
        __ptr<uint> tokens = _tokens._data;
        __ptr<uint> literal_code = literal_codes._data;
        __ptr<u8> literal_length = literal_lengths._data;
        __ptr<uint> distance_code_bits = distance_codes._data;
        __ptr<u8> distance_length = distance_lengths._data;
        __ptr<u8> length_codes = _length_codes._data;
        __ptr<uint> length_base = _length_base._data;
        __ptr<uint> length_extra = _length_extra._data;
        __ptr<uint> distance_base = _distance_base._data;
        __ptr<uint> distance_extra = _distance_extra._data;
        ulong index = 0;
        while (index < token_count) {
            var token = tokens[index];
            index += 1;
            if ((token & _DEFLATE_MATCH) == 0) {
                var literal = token as ulong;
                bits = bits | ((literal_code[literal] as ulong) << count);
                count += literal_length[literal] as ulong;
            } else {
                var length = ((token >> 16) & 511) as ulong;
                var distance = (token & 65535) as ulong;
                var code = length_codes[length] as ulong;
                bits = bits | ((literal_code[257 + code] as ulong) << count);
                count += literal_length[257 + code] as ulong;
                bits = bits | ((length - (length_base[code] as ulong)) << count);
                count += length_extra[code] as ulong;
                var distance_code = _distance_code(distance);
                bits = bits | ((distance_code_bits[distance_code] as ulong) << count);
                count += distance_length[distance_code] as ulong;
                bits = bits | ((distance - (distance_base[distance_code] as ulong)) << count);
                count += distance_extra[distance_code] as ulong;
            }
            _compress_store_64(out, at, bits);
            var whole = count & 56;
            at += whole >> 3;
            bits = bits >> whole;
            count -= whole;
        }
        output._size = at;
        output._version += 1;
        _bits = bits;
        _bit_count = count;
        _write_bits(literal_codes[256] as ulong, literal_lengths[256] as ulong);
    }

    # Writes `count` input bytes from absolute position `start` as one
    # stored block.
    _write_stored(start: ulong, count: ulong, final: bool) {
        _write_bits(_compress_flag(final), 1);
        _write_bits(0, 2);
        _flush_bits();
        _write_little_endian(count, 2);
        _write_little_endian(count ^ 65535, 2);
        output._append_raw(_buffer._data + (start - _base), count);
    }
}

# The number of bytes, up to `max_length`, that `a` and `b` have in common
# at the start, compared eight at a time.
_compress_match_length(a: __ptr<u8>, b: __ptr<u8>, max_length: ulong): ulong {
    ulong length = 0;
    while (length + 8 <= max_length) {
        var difference = _compress_load_64(a, length) ^ _compress_load_64(b, length);
        if (difference != 0) {
            return length + ((difference.trailing_zeros() as ulong) >> 3);
        }
        length += 8;
    }
    while (length < max_length && a[length] == b[length]) {
        length += 1;
    }
    return length;
}

_compress_flag(final: bool): ulong {
    if (final) {
        return 1;
    }
    return 0;
}

# The length of literal/length symbol `symbol` in the fixed code.
_compress_fixed_length(symbol: ulong): ulong {
    if (symbol < 144) {
        return 8;
    }
    if (symbol < 256) {
        return 9;
    }
    if (symbol < 280) {
        return 7;
    }
    return 8;
}

# Run-length encodes code lengths with symbols 16 (repeat the previous 3-6
# times), 17 (3-10 zeros) and 18 (11-138 zeros); each entry is
# `symbol | extra << 8`.
_compress_length_runs(lengths: u8[]): uint[] {
    var runs = Array<uint>();
    var count = lengths.count;
    ulong index = 0;
    while (index < count) {
        var value = lengths[index];
        ulong run = 1;
        while (index + run < count && lengths[index + run] == value) {
            run += 1;
        }
        index += run;
        if (value == 0) {
            while (run >= 11) {
                var take = run;
                if (take > 138) {
                    take = 138;
                }
                runs.append(18 | (((take - 11) as uint) << 8));
                run -= take;
            }
            if (run >= 3) {
                runs.append(17 | (((run - 3) as uint) << 8));
                run = 0;
            }
        } else {
            runs.append(value as uint);
            run -= 1;
            while (run >= 3) {
                var take = run;
                if (take > 6) {
                    take = 6;
                }
                runs.append(16 | (((take - 3) as uint) << 8));
                run -= take;
            }
        }
        while (run > 0) {
            runs.append(value as uint);
            run -= 1;
        }
    }
    return runs;
}

# The Huffman code lengths, at most `limit` bits, for symbols with the
# given counts; 0 for a symbol that does not occur. At least two symbols get
# a code, so every decoder accepts the code.
export _compress_code_lengths(counts: uint[], symbol_count: ulong, limit: ulong): u8[] {
    var lengths = Array<u8>(symbol_count);
    # The symbols that occur, by count then symbol: count << 16 | symbol.
    var leaves = Array<ulong>();
    ulong symbol = 0;
    while (symbol < symbol_count) {
        lengths.append(0);
        if (counts[symbol] != 0) {
            leaves.append(((counts[symbol] as ulong) << 16) | symbol);
        }
        symbol += 1;
    }
    symbol = 0;
    while (leaves.count < 2) {
        if (counts[symbol] == 0) {
            leaves.append(symbol);
        }
        symbol += 1;
    }
    leaves.sort((a, b) => _compress_compare(a, b));
    # Huffman's algorithm with two queues: the sorted leaves, and the
    # internal nodes, which are made in order of weight.
    var leaf_count = leaves.count;
    var node_count = 2 * leaf_count - 1;
    var weights = Array<ulong>(node_count);
    var parents = Array<ulong>(node_count);
    ulong index = 0;
    while (index < node_count) {
        if (index < leaf_count) {
            weights.append(leaves[index] >> 16);
        } else {
            weights.append(0);
        }
        parents.append(0);
        index += 1;
    }
    ulong next_leaf = 0;
    var next_node = leaf_count;
    var made = leaf_count;
    while (made < node_count) {
        var pick = 0;
        while (pick < 2) {
            ulong chosen = 0;
            if (next_leaf < leaf_count && (next_node >= made || weights[next_leaf] <= weights[next_node])) {
                chosen = next_leaf;
                next_leaf += 1;
            } else {
                chosen = next_node;
                next_node += 1;
            }
            weights[made] += weights[chosen];
            parents[chosen] = made;
            pick += 1;
        }
        made += 1;
    }
    # Depths, from the root down: a parent is always made after its children.
    var depths = Array<ulong>(node_count);
    index = 0;
    while (index < node_count) {
        depths.append(0);
        index += 1;
    }
    var level_counts = Array<ulong>(64);
    index = 0;
    while (index < 64) {
        level_counts.append(0);
        index += 1;
    }
    index = node_count - 1;
    while (index > 0) {
        index -= 1;
        depths[index] = depths[parents[index]] + 1;
        if (index < leaf_count) {
            level_counts[depths[index]] += 1;
        }
    }
    # Limit the lengths: move the codes that are too long up to the limit,
    # then lengthen shorter codes until the lengths fit again.
    index = limit + 1;
    while (index < 64) {
        level_counts[limit] += level_counts[index];
        level_counts[index] = 0;
        index += 1;
    }
    ulong total = 0;
    index = 1;
    while (index <= limit) {
        total += level_counts[index] << (limit - index);
        index += 1;
    }
    while (total > ((1 as ulong) << limit)) {
        level_counts[limit] -= 1;
        index = limit - 1;
        while (index > 0) {
            if (level_counts[index] != 0) {
                level_counts[index] -= 1;
                level_counts[index + 1] += 2;
                break;
            }
            index -= 1;
        }
        total -= 1;
    }
    # The rarest symbols get the longest codes.
    ulong leaf = 0;
    var length = limit;
    while (length > 0) {
        var count = level_counts[length];
        while (count > 0) {
            lengths[leaves[leaf] & 65535] = length as u8;
            leaf += 1;
            count -= 1;
        }
        length -= 1;
    }
    return lengths;
}

_compress_compare(a: ulong, b: ulong): int {
    if (a < b) {
        return -1;
    }
    if (a > b) {
        return 1;
    }
    return 0;
}

# The canonical codes for the given code lengths (RFC 1951 section 3.2.2),
# bit-reversed, since codes are written first bit highest into a stream that
# is filled from the lowest bit.
export _compress_canonical_codes(lengths: u8[]): uint[] {
    var counts = Array<uint>(16);
    var next_code = Array<uint>(16);
    var index = 0;
    while (index < 16) {
        counts.append(0);
        next_code.append(0);
        index += 1;
    }
    for (var length in lengths) {
        counts[length as ulong] += 1;
    }
    counts[0] = 0;
    uint code = 0;
    ulong bits = 1;
    while (bits < 16) {
        code = (code + counts[bits - 1]) << 1;
        next_code[bits] = code;
        bits += 1;
    }
    var codes = Array<uint>(lengths.count);
    for (var length in lengths) {
        if (length == 0) {
            codes.append(0);
            continue;
        }
        var size = length as ulong;
        codes.append(_compress_reverse_bits(next_code[size], size));
        next_code[size] += 1;
    }
    return codes;
}
