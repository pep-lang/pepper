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
        if !word.empty() {
            if !this.counts.contains(word) {
                this.order.append(word);
            }
            this.counts[word] = this.counts[word] + 1;
            this.total = this.total + 1;
        }
    }

    # Splits `text` into words at spaces and counts each one.
    add_text(text: String) {
        var word = String();
        for (var c in text) {
            if c == " " {
                this.add(word);
                word = String();
            } else {
                word += c;
            }
        }
        this.add(word);
    }

    count(word: String): int {
        return this.counts[word];
    }
}
