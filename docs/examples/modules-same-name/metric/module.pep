# Lengths in metres.
export struct Length {
    var metres: double;
}

export parse(text: String): Length {
    var length = Length();
    length.metres = text.length as double;
    return length;
}

export unit(): String {
    return "m";
}
