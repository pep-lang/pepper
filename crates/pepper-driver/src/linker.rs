//! POSIX linker: system `ld` with the arg vector from
//! `source/Compiler/Linker.cpp:256-288` (macOS/POSIX only; the Windows
//! `link.exe` path is not ported).

use std::path::{Path, PathBuf};
use std::process::Command;

/// Link obj files into an executable.
pub fn link(
    objects: &[PathBuf],
    output: &Path,
    libraries: &[String],
    library_dirs: &[PathBuf],
) -> Result<(), String> {
    let mut args: Vec<String> = vec![
        "-demangle".to_string(),
        "-dynamic".to_string(),
        "-arch".to_string(),
        "x86_64".to_string(),
        "-o".to_string(),
        output.to_string_lossy().into_owned(),
    ];

    if cfg!(target_os = "macos") {
        args.push("-platform_version".to_string());
        args.push("macos".to_string());
        args.push("12.1.0".to_string());
        args.push("12.3".to_string());
        if let Some(sdk) = Path::new("/Library/Developer/CommandLineTools/SDKs/MacOSX12.sdk")
            .to_str()
        {
            args.push("-syslibroot".to_string());
            args.push(sdk.to_string());
        }
    }

    for obj in objects {
        args.push(obj.to_string_lossy().into_owned());
    }
    for dir in library_dirs {
        args.push(format!("-L{}", dir.display()));
    }
    args.push("-lSystem".to_string());
    for lib in libraries {
        args.push(format!("-l{}", lib));
    }

    let status = Command::new("ld").args(&args).status();
    match status {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => Err(format!("Link failed: ld exited with {}", s)),
        Err(e) => Err(format!("Link failed: {}", e)),
    }
}
