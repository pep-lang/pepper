pub mod parsers;

use std::fs::File;
use std::io::Read;
use std::path::Path;

use crate::ast::{Module, Span};

/// Parse a single `.pep` file from disk.
pub fn parse_file(path: &Path) -> Result<Module, String> {
    let name = path
        .to_str()
        .ok_or_else(|| format!("invalid path: {:?}", path))?;
    let mut file = File::open(path).map_err(|e| format!("cannot open {}: {}", name, e))?;
    let mut content = String::new();
    file.read_to_string(&mut content)
        .map_err(|e| format!("cannot read {}: {}", name, e))?;
    parse_source(name, &content)
}

/// Parse source text into a `Module`.
pub fn parse_source(name: &str, source: &str) -> Result<Module, String> {
    let _guard = parsers::track_source(source.len());
    let mut input: &str = source;
    parsers::parse_module(&mut input).map_err(|_| {
        // Report the parse error at the furthest point parsing reached. PEG
        // backtracking rewinds `input`, so the remaining-slice offset alone
        // underreports the true failure position.
        let offset = parsers::max_pos().min(source.len());
        let p = Span::offset_to_position(source, offset);
        format!("{}:{}:{}: parse error", name, p.line + 1, p.col + 1)
    })
}

#[cfg(test)]
mod tests {
    #[test]
    fn parse_error_reports_furthest_position() {
        // The failure is mid-file; PEG backtracking must not drag the reported
        // position back to line 1.
        let src = "main(): int {\n    var x = ;\n}\n";
        match super::parse_source("t.pep", src) {
            Ok(_) => panic!("expected a parse error"),
            Err(e) => assert!(e.starts_with("t.pep:2:"), "reported position: {}", e),
        }
    }
}
