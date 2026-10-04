# A regex.Regex is [Shared]: one compiled at module scope serves every
# thread at once.

import async;
import regex;

const word = regex.Regex("(?<word>[a-z]+)");
const found_count = async.Atomic<long>(0);

count_words() {
    var i = 0;
    while (i < 200) {
        for (var each in word.find_all("one two three")) {
            if (each.group("word").value().size > 0) {
                found_count.fetch_add(1);
            }
        }
        i += 1;
    }
}

[Test]
shares_one_regex_between_threads() {
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(count_words));
        i += 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    expect_equal(found_count.load(), 4 * 200 * 3);
}
