# The same names as summary.pep's private ones, and private here too.
import "summary";

private const WIDTH: ulong = 12;

private label(name: String): String {
    return $"- {name}";
}

export detail_line(name: String): String {
    return pad(label(name), WIDTH) + "|";
}
