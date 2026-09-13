use pepper::parser;

use std::path::PathBuf;
use std::process::ExitCode;
use clap::Parser;

#[derive(Parser)]
struct Options {
    /// Source files to parse
    source_files: Vec<PathBuf>,

    /// Emit the AST as text instead of just parsing
    #[arg(long)]
    emit_ast: bool,
}

fn main() -> ExitCode {
    let options = Options::parse();

    if options.source_files.is_empty() {
        eprintln!("error: no source files provided");
        return ExitCode::FAILURE;
    }

    let mut had_error = false;

    for path in &options.source_files {
        match parser::parse_file(path) {
            Ok(module) => {
                if options.emit_ast {
                    println!("{}", module);
                } else {
                    eprintln!("parsed {} OK ({} imports, {} declarations)",
                        path.display(),
                        module.imports.len(),
                        module.declarations.len(),
                    );
                }
            }
            Err(e) => {
                eprintln!("error: {}", e);
                had_error = true;
            }
        }
    }

    if had_error {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
