//! `cargo setup` — one cross-platform entry point for provisioning LLVM.
//!
//! Why this exists rather than a build script: the LLVM version is a cargo
//! *feature*, resolved before any build script runs, and `llvm-sys` — a
//! dependency of a dependency — fails to compile before `pepper-codegen`'s
//! build script exists:
//!
//!   error: could not compile `llvm-sys` (lib)
//!   --> llvm-sys-201.1.0/src/lib.rs:533 "No suitable version of LLVM was
//!       found system-wide or pointed to by LLVM_SYS_201_PREFIX"
//!
//! So nothing inside the build can discover LLVM in time to configure it, and
//! the only mechanism that reaches `llvm-sys` without shell state is cargo's
//! `[env]` table in `.cargo/config.toml`. Something has to write that file
//! before the build; this is that something, reachable with one command that
//! is the same on all three platforms.
//!
//! It does not reimplement provisioning: `scripts/setup-llvm.{sh,ps1}` own
//! that, and this picks the right one, finds a shell for it, and reports what
//! happened in terms of the next command to run.

use std::env;
use std::ffi::OsStr;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

/// The workspace manifest, read at compile time so the facts below are derived
/// from the feature table rather than duplicated here. `include_str!` also
/// makes cargo rebuild this when that table changes.
const WORKSPACE_MANIFEST: &str = include_str!("../../Cargo.toml");

/// What `cargo setup --help` prints. The book's contributing/setup.md
/// documents each option it lists, and `pep-doc check` checks that it
/// does.
const USAGE: &str = include_str!("usage.txt");

/// What the arguments asked for.
enum Plan {
    Help,
    Check,
    /// Flags to hand to the platform's setup script.
    Provision(Vec<String>),
}

/// Turn argv into a plan.
///
/// Separated from `main` so the flag handling is testable without running a
/// setup script: it decides what reaches the platform script, and the two
/// scripts disagreed about `--devtools`/`--no-devtools` until it resolved
/// them here.
fn plan(args: &[String]) -> Result<Plan, String> {
    let mut forward: Vec<String> = Vec::new();
    let mut check = false;
    // The last of --devtools / --no-devtools wins, identically on every
    // platform. Forwarding them raw made the two disagree: the shell script
    // applies both in order, while on Windows only --devtools mapped to
    // anything at all.
    let mut devtools: Option<bool> = None;

    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            // `setup` is accepted so that `cargo setup` and
            // `cargo run -p xtask -- setup` both read naturally; provisioning
            // is the only thing this does. A bare `--` arrives when someone
            // writes `cargo setup -- --check`, since the alias already ends
            // in one.
            "setup" | "--" => {}
            "--check" => check = true,
            "-h" | "--help" => return Ok(Plan::Help),
            "--llvm" => match iter.next() {
                Some(major) => {
                    forward.push("--llvm".into());
                    forward.push(major.clone());
                }
                None => return Err("--llvm needs a major version".into()),
            },
            "--devtools" => devtools = Some(true),
            "--no-devtools" => devtools = Some(false),
            "--no-packages" => forward.push(arg.clone()),
            other if other.starts_with("--llvm=") => forward.push(other.into()),
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    match devtools {
        Some(true) => forward.push("--devtools".into()),
        Some(false) => forward.push("--no-devtools".into()),
        None => {}
    }

    // --check wins over provisioning: it is the read-only question.
    if check {
        return Ok(Plan::Check);
    }
    Ok(Plan::Provision(forward))
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let root = repo_root();

    let plan = match plan(&args) {
        Ok(plan) => plan,
        Err(message) => {
            eprintln!("{message}\n\n{}", USAGE.trim_end());
            return ExitCode::FAILURE;
        }
    };

    match plan {
        Plan::Help => {
            println!("{}", USAGE.trim_end());
            ExitCode::SUCCESS
        }
        Plan::Check => {
            report(&root);
            ExitCode::SUCCESS
        }
        // No report afterwards: the setup script already prints the prefix it
        // settled on and the build command for it, and saying it twice reads
        // like something ran twice. `--check` is for asking after the fact.
        Plan::Provision(forward) => match provision(&root, &forward) {
            Ok(()) => ExitCode::SUCCESS,
            Err(message) => {
                eprintln!("{message}");
                ExitCode::FAILURE
            }
        },
    }
}

/// The workspace root, which is this crate's parent directory.
fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("xtask/ always has a parent")
        .to_path_buf()
}

/// Translate the forwarded flags into a PowerShell argument vector.
///
/// Separate from `provision` so it can be asserted on from a non-Windows
/// host too: this mapping is where the platforms drifted apart.
fn powershell_args(script: &Path, forward: &[String]) -> Vec<String> {
    let mut args: Vec<String> = vec![
        "-NoProfile".into(),
        // Windows PowerShell 5.1 defaults to Restricted on client SKUs,
        // which refuses to run any script file at all -- so without this the
        // 5.1 fallback fails on exactly the stock machine it exists to serve
        // ("cannot be loaded because running scripts is disabled on this
        // system"). pwsh accepts the same flag.
        "-ExecutionPolicy".into(),
        "Bypass".into(),
        "-File".into(),
        script.display().to_string(),
    ];

    let mut iter = forward.iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--devtools" => args.push("-DevTools".into()),
            // Windows has no package manager that ships a usable LLVM, so
            // --no-packages means nothing there; accepting and ignoring it
            // keeps one flag set across platforms. --no-devtools is applied
            // through the environment instead, since setup-llvm.ps1 takes
            // that opt-in from PEPPER_SETUP_DEVTOOLS rather than a switch.
            "--no-devtools" | "--no-packages" => {}
            "--llvm" => {
                args.push("-Llvm".into());
                if let Some(major) = iter.next() {
                    args.push(major.clone());
                }
            }
            other if other.starts_with("--llvm=") => {
                args.push("-Llvm".into());
                args.push(other.trim_start_matches("--llvm=").into());
            }
            _ => {}
        }
    }
    args
}

/// Run the platform's setup script, translating the flags it expects.
fn provision(root: &Path, forward: &[String]) -> Result<(), String> {
    // Honoured by clearing the environment opt-in rather than by a flag,
    // because PEPPER_SETUP_DEVTOOLS is how a developer turns devtools on once
    // per machine, and `--no-devtools` has to be able to override that.
    let no_devtools = forward.iter().any(|arg| arg == "--no-devtools");

    if cfg!(windows) {
        let script = root.join("scripts").join("setup-llvm.ps1");
        let script_args = powershell_args(&script, forward);

        // pwsh is PowerShell 7; powershell.exe is the 5.1 that ships with
        // Windows. The script runs under either, and a machine with only 5.1
        // should not have to install anything to get started.
        for shell in ["pwsh", "powershell"] {
            match run(root, shell, &script_args, no_devtools) {
                Ok(()) => return Ok(()),
                Err(RunError::NotFound) => continue,
                Err(RunError::Failed(status)) => {
                    return Err(format!("{shell} exited with {status}"));
                }
            }
        }
        Err("no PowerShell found: expected pwsh or powershell on PATH".into())
    } else {
        let script = root.join("scripts").join("setup-llvm.sh");
        let mut script_args: Vec<String> = vec![script.display().to_string()];
        script_args.extend(forward.iter().cloned());
        match run(root, "bash", &script_args, no_devtools) {
            Ok(()) => Ok(()),
            Err(RunError::NotFound) => Err("bash not found on PATH".into()),
            Err(RunError::Failed(status)) => Err(format!("setup-llvm.sh exited with {status}")),
        }
    }
}

enum RunError {
    NotFound,
    Failed(i32),
}

fn run<S: AsRef<OsStr>>(
    cwd: &Path,
    program: &str,
    args: &[S],
    no_devtools: bool,
) -> Result<(), RunError> {
    let mut command = Command::new(program);
    command.args(args).current_dir(cwd);
    if no_devtools {
        command.env("PEPPER_SETUP_DEVTOOLS", "0");
    }
    match command.status() {
        Ok(status) if status.success() => Ok(()),
        Ok(status) => Err(RunError::Failed(status.code().unwrap_or(-1))),
        Err(error) if error.kind() == ErrorKind::NotFound => Err(RunError::NotFound),
        Err(error) => {
            eprintln!("cannot run {program}: {error}");
            Err(RunError::Failed(-1))
        }
    }
}

/// Report what is configured and the command that builds it.
///
/// The version is a cargo feature, so a prefix alone is not enough to know
/// whether a plain `cargo build` will work: it only does when the provisioned
/// major is the default one.
fn report(root: &Path) {
    let config = root.join(".cargo").join("config.toml");
    let Some((major, prefix)) = configured_prefix(&config) else {
        println!("\nNo LLVM configured yet ({} is absent or has no", config.display());
        println!("LLVM_SYS_<major>1_PREFIX). Run:  cargo run -p xtask -- setup");
        return;
    };

    println!("\nConfigured: LLVM {major} at {prefix}");

    let exists = Path::new(&prefix)
        .join("bin")
        .join(if cfg!(windows) { "llvm-config.exe" } else { "llvm-config" })
        .is_file();
    if !exists {
        println!("  warning: that prefix no longer has bin/llvm-config; re-run setup.");
    }

    match default_major() {
        Some(default) if default == major => println!("Build with:  cargo build"),
        Some(default) => {
            println!("LLVM {major} is not the default ({default}), so name it:");
            println!("  cargo build --no-default-features --features llvm{major}-1");
            println!("  cargo test --workspace --no-default-features --features llvm{major}-1");
        }
        None => println!("Build with:  cargo build"),
    }
}

/// Read `LLVM_SYS_<major>1_PREFIX` back out of the generated cargo config.
fn configured_prefix(config: &Path) -> Option<(String, String)> {
    let text = std::fs::read_to_string(config).ok()?;
    for line in text.lines() {
        let line = line.trim();
        let Some(rest) = line.strip_prefix("LLVM_SYS_") else {
            continue;
        };
        let (major_with_suffix, value) = rest.split_once(" = ")?;
        // LLVM_SYS_201_PREFIX -> major 20: llvm-sys majors are <major> then 1.
        let major = major_with_suffix
            .strip_suffix("_PREFIX")?
            .strip_suffix('1')?
            .to_string();
        // TOML escapes Windows separators; the shell/filesystem wants them single.
        let prefix = value.trim().trim_matches('"').replace("\\\\", "\\");
        return Some((major, prefix));
    }
    None
}

/// The default LLVM major, parsed out of the workspace feature table so it is
/// never a second copy of the pin.
fn default_major() -> Option<String> {
    for line in WORKSPACE_MANIFEST.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("default = [\"llvm") {
            return rest.split('-').next().map(str::to_string);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plan_of(args: &[&str]) -> Plan {
        let owned: Vec<String> = args.iter().map(|a| (*a).to_string()).collect();
        plan(&owned).expect("these arguments are valid")
    }

    fn forwarded(args: &[&str]) -> Vec<String> {
        match plan_of(args) {
            Plan::Provision(forward) => forward,
            _ => panic!("expected a provisioning plan for {args:?}"),
        }
    }

    /// The last of --devtools/--no-devtools wins, and it has to win the same
    /// way on both platforms: forwarding them raw meant the shell script
    /// applied both in order while Windows only understood --devtools, so
    /// `--devtools --no-devtools` provisioned a debugger on one platform and
    /// not the other.
    #[test]
    fn the_last_devtools_flag_wins_on_every_platform() {
        let ps1 = Path::new("setup-llvm.ps1");
        for (args, want_devtools) in [
            (vec!["--devtools"], true),
            (vec!["--no-devtools"], false),
            (vec!["--devtools", "--no-devtools"], false),
            (vec!["--no-devtools", "--devtools"], true),
        ] {
            let forward = forwarded(&args);
            assert_eq!(
                forward.contains(&"--devtools".to_string()),
                want_devtools,
                "shell script flags for {args:?}"
            );
            assert_eq!(
                powershell_args(ps1, &forward).contains(&"-DevTools".to_string()),
                want_devtools,
                "PowerShell switches for {args:?}"
            );
        }
    }

    /// Windows PowerShell refuses to run script files under its default
    /// policy, so the policy flag has to be present and must precede -File:
    /// everything after -File is passed to the script, not to the shell.
    #[test]
    fn powershell_args_bypass_the_execution_policy_before_naming_the_script() {
        let args = powershell_args(Path::new("setup-llvm.ps1"), &["--llvm".into(), "19".into()]);
        let policy = args.iter().position(|a| a == "-ExecutionPolicy").expect("policy flag");
        let file = args.iter().position(|a| a == "-File").expect("-File");
        assert_eq!(args.get(policy + 1).map(String::as_str), Some("Bypass"));
        assert!(policy < file, "-ExecutionPolicy must come before -File: {args:?}");
        assert_eq!(
            &args[file + 1..],
            &["setup-llvm.ps1".to_string(), "-Llvm".to_string(), "19".to_string()],
            "the script and its own parameters follow -File"
        );
    }

    /// `--llvm` reaches both scripts, in each one's spelling.
    #[test]
    fn the_llvm_major_reaches_both_scripts() {
        for args in [vec!["--llvm", "19"], vec!["--llvm=19"]] {
            let forward = forwarded(&args);
            let ps = powershell_args(Path::new("s.ps1"), &forward);
            let major = ps.iter().position(|a| a == "-Llvm").map(|i| ps[i + 1].clone());
            assert_eq!(major.as_deref(), Some("19"), "PowerShell mapping for {args:?}");
            assert!(
                forward.windows(2).any(|w| w == ["--llvm", "19"]) || forward.contains(&"--llvm=19".to_string()),
                "shell mapping for {args:?}: {forward:?}"
            );
        }
    }

    #[test]
    fn check_and_help_do_not_provision_and_bad_input_is_rejected() {
        assert!(matches!(plan_of(&["--check"]), Plan::Check));
        // The alias already ends in `--`, so `cargo setup -- --check` is what
        // people actually type.
        assert!(matches!(plan_of(&["--", "--check"]), Plan::Check));
        assert!(matches!(plan_of(&["setup", "--check"]), Plan::Check));
        assert!(matches!(plan_of(&["-h"]), Plan::Help));
        assert!(plan(&["--llvm".to_string()]).is_err(), "--llvm with no value");
        assert!(plan(&["--wat".to_string()]).is_err(), "unknown flag");
    }

    /// The default major has to be readable from the manifest, since the
    /// report tells the user whether a bare `cargo build` will work.
    #[test]
    fn default_major_is_parsed_from_the_workspace_manifest() {
        let major = default_major().expect("workspace manifest has a default llvm feature");
        assert!(
            major.parse::<u32>().is_ok(),
            "expected a bare major version, got {major:?}"
        );
    }

    #[test]
    fn configured_prefix_reads_both_platforms_config_shapes() {
        let dir = std::env::temp_dir().join(format!("xtask-cfg-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();

        let windows = dir.join("windows.toml");
        std::fs::write(
            &windows,
            "# generated\n[env]\nLLVM_SYS_201_PREFIX = \"C:\\\\Users\\\\x\\\\llvm\\\\20.1.8\"\n",
        )
        .unwrap();
        assert_eq!(
            configured_prefix(&windows),
            Some(("20".into(), "C:\\Users\\x\\llvm\\20.1.8".into())),
            "TOML-escaped separators must be collapsed"
        );

        let unix = dir.join("unix.toml");
        std::fs::write(&unix, "[env]\nLLVM_SYS_181_PREFIX = \"/usr/lib/llvm-18\"\n").unwrap();
        assert_eq!(
            configured_prefix(&unix),
            Some(("18".into(), "/usr/lib/llvm-18".into()))
        );

        let empty = dir.join("empty.toml");
        std::fs::write(&empty, "[alias]\nsetup = \"run -p xtask --\"\n").unwrap();
        assert_eq!(
            configured_prefix(&empty),
            None,
            "a config with an alias but no prefix is not configured"
        );

        std::fs::remove_dir_all(&dir).ok();
    }
}
