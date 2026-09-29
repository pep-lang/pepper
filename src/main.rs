use clap::Parser;
use pepper_driver::Options;
use pepper_driver::parser_diagnostic::{colorize, is_rendered};
use std::io::IsTerminal;
use std::process::ExitCode;

fn main() -> ExitCode {
    let options = Options::parse();
    // Color like clang: on a terminal, unless NO_COLOR is set.
    let color = std::io::stderr().is_terminal() && std::env::var_os("NO_COLOR").is_none_or(|v| v.is_empty());

    if options.source_files.is_empty() {
        eprintln!("error: no source files provided");
        return ExitCode::FAILURE;
    }

    match pepper_driver::run(options) {
        Ok(0) => ExitCode::SUCCESS,
        Ok(code) => ExitCode::from(code as u8),
        Err(e) => {
            let e = if is_rendered(&e) { e } else { format!("error: {}", e) };
            if color {
                eprintln!("{}", colorize(&e));
            } else {
                eprintln!("{}", e);
            }
            ExitCode::FAILURE
        }
    }
}
