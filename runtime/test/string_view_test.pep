# StringView: views of a String's bytes, their read API, conversions, and
# how they stay fail-fast when the String changes.

[Test]
views_read_without_copying() {
    var s = "key = value";
    var eq = s.find("=") as ulong;
    var key = s.view(0, eq);
    expect_true(key == "key ");
    expect_true(key.trim() == "key");
    expect_equal(key.size, 4 as ulong);
    expect_true(s.view(eq + 1, s.size - eq - 1).trim_start() == "value");
    expect_true(key.starts_with("ke") && key.ends_with("y ") && key.contains("ey"));
    expect_equal(key.find("y"), 2 as long);
    expect_equal(key.rfind("z"), -1 as long);
    expect_equal(key.byte_at(1), 'e' as byte);
    expect_true(key.view(1, 2) == "ey");
}

[Test]
slices_count_code_points() {
    var s = "héllo wörld";
    var middle = s.slice(1, 4);
    expect_true(middle == "éll");
    expect_equal(middle.length, 3 as ulong);
    expect_equal(middle.size, 4 as ulong);
    expect_true(middle.slice(0, 1) == "é");
    var copy = middle.to_string();
    expect_true(copy == "éll");
    expect_equal(copy.length, 3 as ulong);
    expect_true(middle.to_string() == "éll");
}

[Test]
split_gives_views() {
    var line = "a,bb,,c";
    var pieces = line.view(0, line.size).split(",");
    expect_equal(pieces.count, 4 as ulong);
    expect_true(pieces[0] == "a" && pieces[1] == "bb" && pieces[2].is_empty && pieces[3] == "c");
    var (key, value) = "name=pepper".view(0, 11).split_once("=").value();
    expect_true(key == "name" && value == "pepper");
    expect_true("none".view(0, 4).split_once("=").is_empty());
}

[Test]
views_compare_and_hash_as_their_text() {
    var s = "apple banana";
    var a = s.view(0, 5);
    var b = s.view(6, 6);
    expect_true(a.compare(b) < 0 && b.compare(a) > 0);
    expect_true(a == "apple".view(0, 5));
    expect_true(hash<StringView>(a) == hash<String>("apple"));
    var counts = HashMap<String, int>();
    counts[a.to_string()] = 1;
    expect_equal(counts["apple"], 1);
}

[Test]
[ShouldPanic("String modified while a view of it is in use")]
a_view_fails_fast_after_its_string_changes() {
    var s = String("abc");
    var v = s.view(0, 2);
    s.append("d");
    var size = v.length;
}

[Test]
[ShouldPanic("String view splits a code point")]
a_view_must_not_split_a_code_point() {
    var s = "é";
    var v = s.view(0, 1);
}

[Test]
[ShouldPanic("String slice out of bounds")]
a_slice_past_the_end_panics() {
    var s = "abc";
    var v = s.slice(1, 4);
}

[Test]
a_default_view_is_empty() {
    var v = StringView();
    expect_true(v.is_empty);
    expect_equal(v.find("a"), -1 as long);
    expect_true(v.to_string() == "");
    expect_true(v.trim().is_empty);
    expect_equal(v.split(",").count, 1 as ulong);
}
