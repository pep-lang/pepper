# Lengths in feet.
export struct Length {
    var feet: double;
}

export parse(text: String): Length {
    var length = Length();
    length.feet = (text.length as double) * 3.0;
    return length;
}

export unit(): String {
    return "ft";
}
