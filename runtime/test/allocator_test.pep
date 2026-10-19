# The small block allocator behind `_pep_malloc`: zeroed,
# aligned blocks of every size, realloc across classes and past the limit,
# blocks freed on another thread than the one that allocated them and handed
# out again, threads that exit and the spans they leave, and
# PEPPER_SMALL_BLOCK_LIMIT.

import async;
import io;
import os;
import process;

# Whether `count` bytes at `p` are all zero.
zeroed(p: __ptr<u8>, count: ulong): bool {
    ulong i = 0;
    while (i < count) {
        if (p[i] != 0) {
            return false;
        }
        i = i + 1;
    }
    return true;
}

fill(p: __ptr<u8>, count: ulong, value: u8) {
    ulong i = 0;
    while (i < count) {
        p[i] = value;
        i = i + 1;
    }
}

[Test]
every_size_is_zeroed_aligned_and_reused_zeroed() {
    ulong size = 1;
    while (size <= 4200) {
        __ptr<u8> first = _pep_malloc(size);
        expect_true(zeroed(first, size));
        expect_equal(unsafe_cast<ulong>(first) % 16, 0);
        fill(first, size, 0xAB);
        _pep_free(first);
        # The same class hands the block back: it must be zero again.
        __ptr<u8> second = _pep_malloc(size);
        expect_true(zeroed(second, size));
        _pep_free(second);
        size = size < 160 ? size + 1 : size + 37;
    }
}

[Test]
small_blocks_up_to_the_limit() {
    var limit = _pep_small_block_limit();
    if (limit == 0) {
        return;
    }
    var small = _pep_malloc(limit);
    var large = _pep_malloc(limit + 1);
    var empty = _pep_malloc(0);
    expect_true(_pep_is_small_block(small));
    expect_false(_pep_is_small_block(large));
    expect_false(_pep_is_small_block(empty));
    _pep_free(small);
    _pep_free(large);
    _pep_free(empty);
}

[Test]
many_live_blocks_are_distinct() {
    var blocks = Array<__ptr<ulong>>();
    ulong i = 0;
    while (i < 20000) {
        __ptr<ulong> block = _pep_malloc(8 + (i % 5) * 16);
        block[0] = i;
        blocks.append(block);
        i = i + 1;
    }
    i = 0;
    while (i < blocks.count) {
        expect_equal(blocks[i][0], i);
        _pep_free(blocks[i]);
        i = i + 1;
    }
}

[Test]
realloc_keeps_the_bytes_and_zeroes_the_growth() {
    __ptr<u8> p = _pep_realloc(__null, 0, 10);
    fill(p, 10, 7);
    ulong size = 10;
    # Within a class, to larger classes, and past the limit to calloc.
    while (size < 9000) {
        var grown = size * 2 + 3;
        p = _pep_realloc(p, size, grown);
        expect_equal(p[0], 7);
        expect_equal(p[9], 7);
        expect_true(zeroed(p + size, grown - size));
        size = grown;
    }
    # And back down into a small class.
    p = _pep_realloc(p, size, 12);
    expect_equal(p[9], 7);
    _pep_free(p);
}

# Strings sent to other threads, which free them.
const lines = async.Channel<String>(64);
const received = async.Atomic<long>(0);

receive_lines() {
    for (var line in lines) {
        received.fetch_add(line.size as long);
    }
}

[Test]
blocks_freed_on_other_threads() {
    var receivers = Array<async.Thread>();
    int i = 0;
    while (i < 3) {
        receivers.append(async.Thread.spawn(receive_lines));
        i = i + 1;
    }
    long sent = 0;
    i = 0;
    while (i < 20000) {
        var line = $"line {i}";
        sent = sent + (line.size as long);
        lines.send(move(line));
        i = i + 1;
    }
    lines.close();
    for (var receiver in receivers) {
        receiver.join();
    }
    expect_equal(received.load(), sent);
}

const finished = async.Atomic<int>(0);

# Builds and drops strings of many sizes, then exits: its cache goes back to
# the shared stacks.
churn() {
    int round = 0;
    while (round < 50) {
        var parts = Array<String>();
        int i = 0;
        while (i < 200) {
            parts.append("x".repeat((i % 90) as ulong));
            i = i + 1;
        }
        round = round + 1;
    }
    finished.fetch_add(1);
}

[Test]
threads_that_exit_return_their_blocks() {
    int wave = 0;
    while (wave < 4) {
        var threads = Array<async.Thread>();
        int i = 0;
        while (i < 4) {
            threads.append(async.Thread.spawn(churn));
            i = i + 1;
        }
        for (var thread in threads) {
            thread.join();
        }
        wave = wave + 1;
    }
    expect_equal(finished.load(), 16);
}

extern void* malloc(ulong size);

# Block addresses passed between threads: raw memory, so the test's own
# allocations do not disturb the allocator's spans.
const _BLOCKS: ulong = 20000;
const addresses: __ptr<ulong> = malloc(_BLOCKS * 8);

free_the_blocks() {
    ulong i = 0;
    while (i < _BLOCKS) {
        _pep_free(unsafe_cast<__ptr<void>>(addresses[i]));
        i = i + 1;
    }
}

allocate_the_blocks() {
    ulong i = 0;
    while (i < _BLOCKS) {
        addresses[i] = unsafe_cast<ulong>(_pep_malloc(48));
        i = i + 1;
    }
}

# Whether `_BLOCKS` new blocks of `size` bytes reuse `addresses`, the
# blocks freed before, apart from at most one span's never-used end; frees
# the new ones.
reuses_the_blocks(size: ulong): bool {
    var freed = HashSet<ulong>();
    ulong i = 0;
    while (i < _BLOCKS) {
        freed.insert(addresses[i]);
        i = i + 1;
    }
    ulong fresh = 0;
    i = 0;
    while (i < _BLOCKS) {
        var block = _pep_malloc(size);
        if (!freed.contains(unsafe_cast<ulong>(block))) {
            fresh = fresh + 1;
        }
        addresses[i] = unsafe_cast<ulong>(block);
        i = i + 1;
    }
    free_the_blocks();
    # A span holds 64 KiB of blocks.
    return fresh <= 65536 / size;
}

check_the_blocks_are_reused() {
    expect_true(reuses_the_blocks(48));
}

[Test]
blocks_freed_on_another_thread_are_handed_out_again() {
    if (_pep_small_block_limit() < 48) {
        return;
    }
    ulong i = 0;
    while (i < _BLOCKS) {
        addresses[i] = unsafe_cast<ulong>(_pep_malloc(48));
        i = i + 1;
    }
    # The blocks fill several spans, all full now; another thread frees
    # every one, and this thread, their spans' owner, takes them back.
    async.Thread.spawn(free_the_blocks).join();
    expect_true(reuses_the_blocks(48));
}

[Test]
spans_of_exited_threads_are_adopted() {
    if (_pep_small_block_limit() < 48) {
        return;
    }
    # A thread fills spans and exits, leaving them to their class's pool;
    # this thread frees the blocks, and a new thread adopts the spans.
    async.Thread.spawn(allocate_the_blocks).join();
    free_the_blocks();
    async.Thread.spawn(check_the_blocks_are_reused).join();
}

[Test]
limit_from_the_environment() {
    var limit = os.environment("PEPPER_SMALL_BLOCK_LIMIT");
    var expected: ulong = 128;
    if (limit.is_value()) {
        expected = ulong.parse(limit.value()).value();
    }
    expect_equal(_pep_small_block_limit(), expected > 4096 ? 4096 : expected);
}

[Test]
a_limit_of_zero_turns_the_allocator_off() {
    var self = process.executable_path().value();
    for (var limit in ["0", "512", "100000"]) {
        var run = process
            .Command(self.to_string())
            .argument("--run")
            .argument("limit_from_the_environment")
            .environment("PEPPER_SMALL_BLOCK_LIMIT", limit)
            .run();
        expect_true(run.value().status.success());
    }
}
