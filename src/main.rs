use clap::Parser;
use pepper_driver::Options;
use pepper_driver::parser_diagnostic::{colorize, is_rendered};
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut options = Options::parse_from(pepper_driver::options::normalize_args(std::env::args_os()));
    let color = pepper_driver::stderr_color();

    // With no source file, build the project whose pep.toml is here or above.
    if let Err(e) = options.apply_project() {
        let e = if is_rendered(&e) { e } else { format!("error: {}", e) };
        eprintln!("{}", if color { colorize(&e) } else { e });
        return ExitCode::FAILURE;
    }

    // Compile on a thread with the stack the driver needs; the main
    // thread's is fixed by the linker (1 MB on Windows).
    let result = std::thread::Builder::new()
        .stack_size(pepper_driver::STACK_SIZE)
        .spawn(move || pepper_driver::run(options))
        .expect("start the compiler thread")
        .join();
    let Ok(result) = result else {
        // The panic has already printed.
        return ExitCode::from(101);
    };
    match result {
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
