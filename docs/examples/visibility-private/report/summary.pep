# `private` keeps these to this file: detail.pep may declare its own
# `WIDTH` and `label` without a clash.
private const WIDTH: ulong = 10;

private label(count: int): String {
    return $"{count} item(s)";
}

# Module-internal: no modifier, so detail.pep can use it too.
pad(text: String, width: ulong): String {
    if (text.size >= width) {
        return text;
    }
    return text + " ".repeat(width - text.size);
}

export summary_line(count: int): String {
    return pad(label(count), WIDTH);
}
