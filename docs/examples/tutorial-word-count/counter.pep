# Counts how often each word occurs in some text.
export struct WordCounter {
    var counts: HashMap<String, int>;
    var order: String[];    # each distinct word, in the order first seen
    var total: int;

    construct() {
        this.counts = HashMap<String, int>();
        this.order = Array<String>();
        this.total = 0;
    }

    add(word: String) {
        if !word.is_empty {
            if !this.counts.contains(word) {
                this.order.append(word);
            }
            this.counts[word] = this.counts[word] + 1;
            this.total = this.total + 1;
        }
    }

    # Splits `text` into words at spaces and counts each one. `add` skips
    # the empty pieces that runs of spaces leave.
    add_text(text: String) {
        for (var word in text.split(" ")) {
            this.add(word);
        }
    }

    count(word: String): int {
        return this.counts[word];
    }
}
