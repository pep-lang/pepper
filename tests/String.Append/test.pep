

main(): int {
    var str = "TEST";
    var ret = str += "ING";
    assert(ret == str, "ret == str");
    assert(str == "TESTING", "str == 'TESTING'");
    str.append("!");
    assert(str == "TESTING!", "str == 'TESTING!'");
    return str.length - "TESTING!".length;
}
