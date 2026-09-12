
import "support";

extern void memcpy(void* dest, void* src, ulong size);

assert(condition: bool, msg: __ptr<char>): void {
    if (!condition) {
        panic(msg);
    }
}
