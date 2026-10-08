## BLAKE3: 32-byte digests, faster than SHA-256 in hardware without SHA
## instructions, and the hash the compiler's build cache keys objects with.

import "hex";
import "words";

# Domain flags of the compression function.
const _CHUNK_START: uint = 1;
const _CHUNK_END: uint = 2;
const _PARENT: uint = 4;
const _ROOT: uint = 8;
# The bytes in a chunk, the leaves of BLAKE3's tree.
const _CHUNK_SIZE: ulong = 1024;

## An incremental BLAKE3 hasher: feed it bytes with `update`, any number of
## times and in pieces of any size, then read the 32-byte digest with
## `finish`.
##
## This is a portable implementation of the default hash mode, one block
## at a time; it does not use SIMD or threads, so it runs well below the
## speed of the official C and Rust implementations. The digests are the
## same. `finish` resets the hasher, so it can hash a new input.
##
## @example
##     import digest;
##
##     var hasher = digest.Blake3();
##     hasher.update("hello ");
##     hasher.update("world");
##     assert(hasher.finish_hex() == digest.to_hex(digest.blake3("hello world")), "same digest");
export struct Blake3 {
    # The key words: BLAKE3's IV in the default hash mode.
    var _key: uint[];
    # The chaining value of the chunk being hashed, and its index.
    var _chunk_value: uint[];
    var _chunk_counter: ulong;
    # The chunk's input not yet compressed: `_block_size` of 64 bytes, the
    # rest zero, and how many of its blocks are compressed already.
    var _block: u8[];
    var _block_size: ulong;
    var _blocks_compressed: ulong;
    # The chaining values of completed subtrees, 8 words each, at most one
    # per level of the tree (54 levels hold 2^64 bytes).
    var _stack: uint[];
    var _stack_size: ulong;
    # Scratch space: a block's 16 message words, and the compression output.
    var _words: uint[];
    var _state: uint[];
    # The message word permutation for each of the 7 rounds.
    var _schedule: u8[];

    ## Creates a hasher in the initial state, with no input.
    construct() {
        _key = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
        _chunk_value = _digest_words(8);
        _block = _digest_bytes(64);
        _stack = _digest_words(54 * 8);
        _words = _digest_words(16);
        _state = _digest_words(16);
        _schedule = _digest_blake3_schedule();
        reset();
    }

    ## Discards the input given so far, returning the hasher to its initial
    ## state.
    reset() {
        _start_chunk(0);
        _stack_size = 0;
    }

    ## Hashes `bytes` as the next part of the input.
    ##
    ## @param bytes the bytes to add
    update(bytes: u8[]) {
        _update_raw(bytes._data, bytes.count);
    }

    ## Hashes `count` bytes of `bytes`, from index `start`, as the next part
    ## of the input; those past the end of `bytes` are left out.
    ##
    ## @param bytes the bytes
    ## @param start the index of the first byte to add
    ## @param count how many bytes to add
    update_range(bytes: u8[], start: ulong, count: ulong) {
        if (start >= bytes.count) {
            return;
        }
        var n = count < bytes.count - start ? count : bytes.count - start;
        _update_raw(unsafe_cast<__ptr<u8>>(bytes._data) + start, n);
    }

    ## Hashes the UTF-8 bytes of `text` (without a terminating NUL) as the
    ## next part of the input.
    ##
    ## @param text the text to add
    update(text: String) {
        _update_raw(unsafe_cast<__ptr<u8>>(text.c_str()), text.size);
    }

    ## Returns the 32-byte digest of the input given since the hasher was
    ## created or last reset, then resets it.
    ##
    ## @returns the digest
    finish(): u8[] {
        # The last chunk is the root when it is the only one; otherwise
        # fold it into the stacked subtrees from the right, and the last
        # parent is the root.
        var flags = _chunk_flags() | _CHUNK_END;
        _load_block_words();
        var input_value = _chunk_value._data;
        var counter = _chunk_counter;
        var block_size = _block_size as uint;
        var remaining = _stack_size;
        while (remaining > 0) {
            remaining -= 1;
            _compress(input_value, counter, block_size, flags);
            var words = _words._data;
            var parent = _stack._data + remaining * 8;
            ulong index = 0;
            while (index < 8) {
                words[8 + index] = _state[index];
                words[index] = parent[index];
                index += 1;
            }
            input_value = _key._data;
            counter = 0;
            block_size = 64;
            flags = _PARENT;
        }
        _compress(input_value, counter, block_size, flags | _ROOT);
        var out = Array<u8>(32);
        ulong index = 0;
        while (index < 8) {
            _digest_append_le(out, _state[index]);
            index += 1;
        }
        reset();
        return out;
    }

    ## Returns the digest as `finish` does, written as 64 lowercase
    ## hexadecimal digits.
    ##
    ## @returns the digest in hexadecimal
    finish_hex(): String {
        return to_hex(finish());
    }

    _update_raw(data: __ptr<u8>, size: ulong) {
        ulong offset = 0;
        while (offset < size) {
            # A full chunk is closed only once more input arrives, since
            # the last chunk is finished differently.
            if (_blocks_compressed * 64 + _block_size == _CHUNK_SIZE) {
                _finish_chunk();
            }
            if (_block_size == 64) {
                _load_block_words();
                _compress(_chunk_value._data, _chunk_counter, 64, _chunk_flags());
                _keep_chaining_value(_chunk_value._data);
                _blocks_compressed += 1;
                _block_size = 0;
                _digest_zero(_block._data, 64);
            }
            var take = 64 - _block_size;
            if (take > size - offset) {
                take = size - offset;
            }
            _digest_copy(_block._data + _block_size, data + offset, take);
            _block_size += take;
            offset += take;
        }
    }

    # The flags of the chunk's next block.
    _chunk_flags(): uint {
        return _blocks_compressed == 0 ? _CHUNK_START : 0;
    }

    # Starts chunk `counter` with an empty block.
    _start_chunk(counter: ulong) {
        ulong index = 0;
        while (index < 8) {
            _chunk_value[index] = _key[index];
            index += 1;
        }
        _chunk_counter = counter;
        _block_size = 0;
        _blocks_compressed = 0;
        _digest_zero(_block._data, 64);
    }

    # Closes the full chunk: pushes its chaining value onto the stack,
    # merging completed subtrees, and starts the next chunk.
    _finish_chunk() {
        _load_block_words();
        _compress(_chunk_value._data, _chunk_counter, 64, _chunk_flags() | _CHUNK_END);
        var total = _chunk_counter + 1;
        # Each trailing zero bit of the chunk count completes a subtree:
        # merge it with its left sibling on the stack.
        while ((total & 1) == 0) {
            _stack_size -= 1;
            var words = _words._data;
            var left = _stack._data + _stack_size * 8;
            ulong index = 0;
            while (index < 8) {
                words[8 + index] = _state[index];
                words[index] = left[index];
                index += 1;
            }
            _compress(_key._data, 0, 64, _PARENT);
            total = total >> 1;
        }
        _keep_chaining_value(_stack._data + _stack_size * 8);
        _stack_size += 1;
        _start_chunk(_chunk_counter + 1);
    }

    # Copies the compression output's first 8 words (a chaining value) to
    # `target`.
    _keep_chaining_value(target: __ptr<uint>) {
        var state = _state._data;
        ulong index = 0;
        while (index < 8) {
            target[index] = state[index];
            index += 1;
        }
    }

    # Loads the chunk's block into the message words.
    _load_block_words() {
        var words = _words._data;
        var block = _block._data;
        ulong index = 0;
        while (index < 16) {
            words[index] = _digest_load_le(block, index * 4);
            index += 1;
        }
    }

    # The compression function over the message words: leaves its 16-word
    # output in `_state`.
    _compress(chaining_value: __ptr<uint>, counter: ulong, block_size: uint, flags: uint) {
        var s = _state._data;
        var m = _words._data;
        ulong index = 0;
        while (index < 8) {
            s[index] = chaining_value[index];
            index += 1;
        }
        # The IV, not the key, fills these words in every mode.
        s[8] = 0x6a09e667;
        s[9] = 0xbb67ae85;
        s[10] = 0x3c6ef372;
        s[11] = 0xa54ff53a;
        s[12] = counter as uint;
        s[13] = (counter >> 32) as uint;
        s[14] = block_size;
        s[15] = flags;
        var order = _schedule._data;
        ulong round = 0;
        while (round < 7) {
            var p = order + round * 16;
            _digest_blake3_mix(s, 0, 4, 8, 12, m[p[0]], m[p[1]]);
            _digest_blake3_mix(s, 1, 5, 9, 13, m[p[2]], m[p[3]]);
            _digest_blake3_mix(s, 2, 6, 10, 14, m[p[4]], m[p[5]]);
            _digest_blake3_mix(s, 3, 7, 11, 15, m[p[6]], m[p[7]]);
            _digest_blake3_mix(s, 0, 5, 10, 15, m[p[8]], m[p[9]]);
            _digest_blake3_mix(s, 1, 6, 11, 12, m[p[10]], m[p[11]]);
            _digest_blake3_mix(s, 2, 7, 8, 13, m[p[12]], m[p[13]]);
            _digest_blake3_mix(s, 3, 4, 9, 14, m[p[14]], m[p[15]]);
            round += 1;
        }
        index = 0;
        while (index < 8) {
            s[index] = s[index] ^ s[index + 8];
            s[index + 8] = s[index + 8] ^ chaining_value[index];
            index += 1;
        }
    }
}

## Returns the BLAKE3 digest of `bytes`.
##
## @param bytes the input
## @returns the 32-byte digest
## @example
##     import digest;
##
##     var empty = "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";
##     assert(digest.to_hex(digest.blake3(Array<u8>())) == empty, "BLAKE3 of nothing");
export blake3(bytes: u8[]): u8[] {
    var hasher = Blake3();
    hasher.update(bytes);
    return hasher.finish();
}

## Returns the BLAKE3 digest of the UTF-8 bytes of `text`.
##
## @param text the input
## @returns the 32-byte digest
export blake3(text: String): u8[] {
    var hasher = Blake3();
    hasher.update(text);
    return hasher.finish();
}

# The quarter-round G on words `a`, `b`, `c` and `d` of `s`, mixing in the
# message words `x` and `y`.
_digest_blake3_mix(s: __ptr<uint>, a: ulong, b: ulong, c: ulong, d: ulong, x: uint, y: uint) {
    s[a] = s[a].wrapping_add(s[b]).wrapping_add(x);
    s[d] = _digest_rotate_right(s[d] ^ s[a], 16);
    s[c] = s[c].wrapping_add(s[d]);
    s[b] = _digest_rotate_right(s[b] ^ s[c], 12);
    s[a] = s[a].wrapping_add(s[b]).wrapping_add(y);
    s[d] = _digest_rotate_right(s[d] ^ s[a], 8);
    s[c] = s[c].wrapping_add(s[d]);
    s[b] = _digest_rotate_right(s[b] ^ s[c], 7);
}

# The message word order of each of the 7 rounds: the identity, then each
# row the permutation [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]
# applied to the row before.
_digest_blake3_schedule(): u8[] {
    u8[] permutation = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8];
    var schedule = Array<u8>(7 * 16);
    ulong index = 0;
    while (index < 16) {
        schedule.append(index as u8);
        index += 1;
    }
    ulong round = 1;
    while (round < 7) {
        index = 0;
        while (index < 16) {
            schedule.append(schedule[(round - 1) * 16 + permutation[index]]);
            index += 1;
        }
        round += 1;
    }
    return schedule;
}
