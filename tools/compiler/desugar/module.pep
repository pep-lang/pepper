## The pass between parsing and linking: `desugar(module)` rewrites the
## syntax tree as the source wrote it (`parse.parse_written`) into the tree
## `parse.parse` returns. See `desugar.pep`.
export * from "desugar";
