# The string is built at run time (the program's argument count is 1), so
# its length is not a constant.
main(args: String[]): int {
    var text = "TE";
    if (args.count == 1) {
        text = text + "ST";
    }
    if (text.length != 4) { return -1; }
    if (text != "TEST") { return -2; }
    return 0;
}
