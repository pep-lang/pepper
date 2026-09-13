pub mod parsers;

use std::fs::File;
use std::io::Read;
use std::path::Path;

use crate::ast::Module;

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
    let mut input: &str = source;
    parsers::parse_module(&mut input)
        .map_err(|_| {
            // Try to report position
            let line = source[..source.len() - input.len()].lines().count();
            let col = source[..source.len() - input.len()]
                .rfind('\n')
                .map(|i| source[..source.len() - input.len()].len() - i - 1)
                .unwrap_or(source[..source.len() - input.len()].len());
            format!("{}:{}:{}: parse error", name, line + 1, col + 1)
        })
}
