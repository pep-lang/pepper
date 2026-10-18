<!-- Generated from runtime/random/entropy.pep by `pep-doc reference`. Do not edit. -->

# Entropy

Secure random bytes from the operating system: `getentropy` on Linux,
Android, macOS, iOS and WASI, and `BCryptGenRandom` on Windows. They are
unpredictable, so they suit keys, tokens and identifiers, but each call
asks the kernel; a `Generator` is much faster for everything else.

Source: `runtime/random/entropy.pep`
