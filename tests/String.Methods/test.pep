main(): int {
    print("Hello world!");
    var s = "TEST";
    s.append("ING");
    print(s);
    print(s.substr(0, 4));
    assert(s == "TESTING", "append then compare");
    assert(s.starts_with("TEST"), "starts_with");
    assert(s.ends_with("ING"), "ends_with");
    assert(s.contains("STI"), "contains");
    assert(s.find("STI") == 2, "find returns a byte offset");
    assert(!s.is_empty, "empty");
    assert(s[0] == "T", "index yields a one-character string");
    return s.length - 7;
}
