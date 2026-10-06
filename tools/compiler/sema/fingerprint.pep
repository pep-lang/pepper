## A fingerprint of a model value: a 64-bit hash the generated
## `fingerprint()` methods of `model.pep` feed, so a pass can tell whether
## a callable changed since it last looked without keeping a copy.

## A running hash: FNV-style over 64-bit words, folded after each.
export struct Fingerprint {
    ## The hash so far.
    var value: ulong = 7809847782465536322;

    construct() {}

    ## Adds a number.
    ##
    ## @param word the number
    add(word: ulong) {
        value = (value ^ word).wrapping_mul(1099511628211);
        value = value ^ (value >> 29);
    }

    ## Adds a string: its hash and its size.
    ##
    ## @param text the string
    add_text(text: String) {
        add(hash<String>(text));
        add(text.size);
    }
}
