# The module's interface: only what this file exports reaches importers.
export * from "stock";

# `rules.pep` exports nothing, so importing it only makes it part of the
# module.
import "rules";
