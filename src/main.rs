use clap::Parser;
use pepper_driver::Options;
use std::process::ExitCode;

fn main() -> ExitCode {
    let options = Options::parse();

    if options.source_files.is_empty() {
        eprintln!("error: no source files provided");
        return ExitCode::FAILURE;
    }

    match pepper_driver::run(options) {
        Ok(0) => ExitCode::SUCCESS,
        Ok(code) => ExitCode::from(code as u8),
        Err(e) => {
            eprintln!("error: {}", e);
            ExitCode::FAILURE
        }
    }
}
