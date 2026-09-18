
import "support";

extern void memcpy(void* dest, void* src, ulong size);

assert(condition: bool, msg: string): void {
    if (!condition) {
        panic(msg.c_str());
    }
}
