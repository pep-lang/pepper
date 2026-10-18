## UUIDs (RFC 9562): 128-bit identifiers, written as
## `0190163d-8694-739b-aea5-966c26f8ad91`.
##
## Bring it in with `import uuid` (or `import [Uuid] from uuid`). `Uuid.v4()`
## makes a random one; `Uuid.v7()` puts the time first, so ids made later
## sort later, which keeps database indexes compact. Both draw their random
## bits from the operating system's secure source (`random.bytes`).
##
## @example
##     import uuid;
##
##     main(): int {
##         var id = uuid.Uuid.v4();
##         var text = id.to_string();                       # such as 9b2c3c1e-...
##         assert(uuid.Uuid.parse(text).value() == id, "round trip");
##         assert(id.version() == 4, "random");
##         return 0;
##     }

import os;
import random;

## A UUID, as a [value struct](../language/value-structs.md) of two 64-bit
## halves: `==` compares them and `hash` hashes them, so a `Uuid` works as
## a map key.
##
## @example
##     var id = Uuid.parse("0190163D-8694-739B-AEA5-966C26F8AD91").value();
##     assert(id.version() == 7, "the version digit");
##     assert(id.to_string() == "0190163d-8694-739b-aea5-966c26f8ad91", "lowercase");
[Value]
export struct Uuid {
    ## The first 8 bytes, the first byte in the top bits.
    var high: ulong;
    ## The last 8 bytes, the first of them in the top bits.
    var low: ulong;

    ## Makes the UUID with these halves; `Uuid(0, 0)` is the nil UUID.
    ##
    ## @param high the first 8 bytes, the first byte in the top bits
    ## @param low the last 8 bytes, the first of them in the top bits
    construct(high: ulong, low: ulong) {
        this.high = high;
        this.low = low;
    }

    ## Returns a new random UUID (version 4): 122 random bits.
    ##
    ## @returns the UUID
    ## @panics if the operating system cannot give random bytes, which only a broken system does
    static v4(): Uuid {
        var high = (random.secure_ulong() & ~0xf000) | 0x4000;
        return Uuid(high, _uuid_variant(random.secure_ulong()));
    }

    ## Returns a new time-ordered UUID (version 7): the wall clock's Unix
    ## time in milliseconds in the first 48 bits, then 74 random bits. Ids
    ## made in different milliseconds sort by time, both as values and as
    ## text; ids made in the same millisecond are in no particular order.
    ##
    ## @returns the UUID
    ## @panics if the operating system cannot give random bytes, which only a broken system does
    static v7(): Uuid {
        var milliseconds = os.SystemTime.now().unix_milliseconds() as ulong;
        var high = (milliseconds << 16) | 0x7000 | (random.secure_ulong() & 0xfff);
        return Uuid(high, _uuid_variant(random.secure_ulong()));
    }

    ## Returns the UUID that `text` writes: 32 hexadecimal digits, either
    ## case, in groups of 8, 4, 4, 4 and 12 separated by `-`.
    ##
    ## @param text the UUID as text, such as `0190163d-8694-739b-aea5-966c26f8ad91`
    ## @returns the UUID, or an error when `text` is not in that form
    static parse(text: String): Result<Uuid> {
        var data = text.bytes();
        if (data.count != 36) {
            return _uuid_invalid(text);
        }
        ulong high = 0;
        ulong low = 0;
        ulong digits = 0;
        for (var index in 0..36) {
            var c = data[index as ulong] as int;
            if (index == 8 || index == 13 || index == 18 || index == 23) {
                if (c != '-') {
                    return _uuid_invalid(text);
                }
                continue;
            }
            var value = _pep_hex_digit(c);
            if (value < 0) {
                return _uuid_invalid(text);
            }
            if (digits < 16) {
                high = (high << 4) | value as ulong;
            } else {
                low = (low << 4) | value as ulong;
            }
            digits += 1;
        }
        return Result<Uuid>.ok(Uuid(high, low));
    }

    ## Returns the version: 4 for `v4`, 7 for `v7`, 0 for the nil UUID.
    ##
    ## @returns the version digit, from 0 to 15
    version(): int {
        return ((high >> 12) & 15) as int;
    }

    ## Returns the UUID's 16 bytes, `high` first, as databases and binary
    ## formats store it.
    ##
    ## @returns 16 bytes
    bytes(): u8[] {
        var out = Array<u8>(16);
        for (var shift in 0..8) {
            out.append((high >> ((7 - shift) * 8) as ulong) as u8);
        }
        for (var shift in 0..8) {
            out.append((low >> ((7 - shift) * 8) as ulong) as u8);
        }
        return out;
    }

    ## Returns the UUID as 32 lowercase hexadecimal digits in groups of 8,
    ## 4, 4, 4 and 12, such as `0190163d-8694-739b-aea5-966c26f8ad91`.
    ##
    ## @returns the UUID as text, 36 characters
    to_string(): String {
        var hex = $"{high:016x}{low:016x}";
        return $"{hex.substr_bytes(0, 8)}-{hex.substr_bytes(8, 4)}-{hex.substr_bytes(12, 4)}-{hex.substr_bytes(16, 4)}-{hex.substr_bytes(20, 12)}";
    }
}

extend Uuid with ToString;

# `low` with the RFC 9562 variant, binary 10, in its top two bits.
_uuid_variant(low: ulong): ulong {
    return (low & 0x3fffffffffffffff) | 0x8000000000000000;
}

_uuid_invalid(text: String): Result<Uuid> {
    return Result<Uuid>.err(Error($"invalid UUID '{text}': expected the form 0190163d-8694-739b-aea5-966c26f8ad91"));
}
