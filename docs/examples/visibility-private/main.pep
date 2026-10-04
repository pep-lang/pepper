import "report";

main(): int {
    assert(summary_line(3) == "3 item(s) ", "summary.pep's own label and width");
    assert(detail_line("pen") == "- pen       |", "detail.pep's own label and width");
    # `label(3)` here would be an error: it is private to summary.pep.
    return 0;
}
