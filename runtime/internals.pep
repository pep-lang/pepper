
import "support";

extern void memcpy(void* dest, void* src, ulong size);

# The message is a raw `char*`, not a `string`: codegen passes string
# literals as their global pointers (no temporary allocation), so hot paths
# like array index bounds checks stay allocation-free. Non-literal messages
# are lowered to `msg.c_str()` at the call site.
assert(condition: bool, msg: char*): void {
    if (!condition) {
        panic(msg);
    }
}
