import "sizes";

main(): int {
    assert(PIXEL_BYTES == 4, "one byte per field of Pixel");
    assert(LAST_CHANNEL == Channel.Alpha, "the last case of Channel");
    return 0;
}
