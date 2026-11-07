import "sizes";

main(): int {
    assert(PIXEL_BYTES == 4, "one byte per field of Pixel");
    assert(LAST_CHANNEL == Channel.Alpha, "the last case of Channel");
    assert(PIXEL_NAME == "Pixel", "the name of Pixel");
    return 0;
}
