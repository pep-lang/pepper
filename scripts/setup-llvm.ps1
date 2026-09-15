#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Provision the LLVM toolchain that llvm-sys (via inkwell) links against, and
    point cargo at it. Windows counterpart of scripts/setup-llvm.sh.

.DESCRIPTION
    llvm-sys finds LLVM by running `<prefix>/bin/llvm-config` and matching its
    major version. The LLVM builds shipped by winget/scoop/chocolatey and the
    llvm.org .exe/.msi installers contain neither llvm-config nor the component
    libraries -- only LLVM-C.dll and its import lib -- so they cannot satisfy it.

    The official `clang+llvm-<ver>-x86_64-pc-windows-msvc.tar.xz` release asset
    is a complete install tree: llvm-config.exe, every LLVM*.lib, LLVM-C.dll,
    and the clang/lld/llc/lli/opt tools. This script downloads it (cached),
    extracts it under $env:LOCALAPPDATA\pepper\llvm, and writes
    .cargo/config.toml so cargo sees LLVM_SYS_<major>_PREFIX with no shell setup.

    Note that Pepper links LLVM-C.dll rather than the static libraries on
    Windows, because those are built against the static CRT; see
    crates/pepper-codegen/build.rs.

    Idempotent: re-running with a valid install only rewrites the cargo config.

.PARAMETER DevTools
    Also install the debugger (lldb, lldb-dap, lldb-server). Equivalent to
    setting PEPPER_SETUP_DEVTOOLS=1. Off by default because it needs a second,
    larger download that the build itself does not require.

.PARAMETER Force
    Re-download and re-extract even if a valid install is already present.

.EXAMPLE
    pwsh -File scripts/setup-llvm.ps1 -DevTools

.EXAMPLE
    $env:PEPPER_SETUP_DEVTOOLS = '1'; pwsh -File scripts/setup-llvm.ps1
#>
[CmdletBinding()]
param(
    [switch]$DevTools,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Dictated by the inkwell feature in crates/*/Cargo.toml:
#   inkwell "llvm22-1" -> llvm-sys 221.x -> LLVM 22.1.x
#
# Changing this? Re-run the llvm-package workflow afterwards
# (gh workflow run llvm-package.yml). The CI packages are per-version, and a
# missing one does not fail: CI silently reverts to multi-GB full installs.
#
# This line is also parsed by ci-provision-llvm.sh to locate the prefix on
# Windows, so keep the `$LlvmVersion = '<version>'` shape.
$LlvmVersion = '22.1.8'
$LlvmMajor = '22'
$LlvmSysMajor = '221'

# liblldb.dll is linked against this exact CPython minor version and the
# llvm.org installer does not bundle it, so the embeddable runtime is placed
# next to lldb.exe. Bump this only if a later LLVM switches Python version
# (`lldb.exe --version` failing with "unable to find pythonXYZ.dll" is the tell).
$LldbPythonVersion = '3.11.9'
$LldbPythonDll = 'python311.dll'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Root = Join-Path $env:LOCALAPPDATA 'pepper'
$Prefix = Join-Path $Root "llvm\$LlvmVersion"
$CacheDir = Join-Path $Root 'cache'
$Asset = "clang+llvm-$LlvmVersion-x86_64-pc-windows-msvc.tar.xz"
$Archive = Join-Path $CacheDir $Asset
$Url = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LlvmVersion/$Asset"

# Windows' bundled bsdtar, resolved absolutely. See its use below for why PATH
# is not good enough.
$script:WindowsTar = Join-Path $env:SystemRoot 'System32\tar.exe'

# PEPPER_SETUP_DEVTOOLS lets a dev opt in once (user/CI environment) instead of
# remembering the flag on every run.
$envDevTools = $env:PEPPER_SETUP_DEVTOOLS
if (-not $DevTools -and $envDevTools) {
    if ($envDevTools -notin @('', '0', 'false', 'no')) {
        $DevTools = $true
    }
}

function Get-Download {
    param([string]$Uri, [string]$Destination, [string]$Label)
    if ((Test-Path $Destination) -and -not $Force) {
        Write-Host "Using cached $Destination"
        return
    }
    Write-Host "Downloading $Label ..."
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    curl.exe -L --fail --progress-bar -o "$Destination.part" $Uri
    if ($LASTEXITCODE -ne 0) { throw "download failed: $Uri" }
    Move-Item -Force "$Destination.part" $Destination
}

function Test-LlvmPrefix {
    param([string]$Path)
    $config = Join-Path $Path 'bin\llvm-config.exe'
    if (-not (Test-Path $config)) { return $false }
    # Windows links the DLL and its import lib; check both so a half-extracted
    # tree is treated as unusable rather than failing later at link time.
    if (-not (Test-Path (Join-Path $Path 'lib\LLVM-C.lib'))) { return $false }
    if (-not (Test-Path (Join-Path $Path 'bin\LLVM-C.dll'))) { return $false }
    $reported = (& $config --version 2>$null)
    return $reported -and $reported.Split('.')[0] -eq $LlvmMajor
}

function Find-SevenZip {
    $candidates = @(
        (Get-Command '7z.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
        (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'),
        (Join-Path $env:USERPROFILE 'scoop\apps\7zip\current\7z.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

function Install-DevTools {
    $lldb = Join-Path $Prefix 'bin\lldb.exe'
    if ((Test-Path $lldb) -and -not $Force) {
        Write-Host "lldb already installed at $lldb"
        return
    }

    # lldb is absent from the clang+llvm tarball; only the llvm.org installer
    # carries it. That installer is NSIS, so extracting it (rather than running
    # it) needs 7-Zip -- which avoids touching the registry or system PATH.
    $sevenZip = Find-SevenZip
    if (-not $sevenZip) {
        throw "7-Zip is required to extract lldb from the LLVM installer. Install it (winget install 7zip.7zip) and re-run with -DevTools."
    }

    $installerAsset = "LLVM-$LlvmVersion-win64.exe"
    $installer = Join-Path $CacheDir $installerAsset
    Get-Download `
        -Uri "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LlvmVersion/$installerAsset" `
        -Destination $installer `
        -Label "$installerAsset (~434 MB, debugger only)"

    Write-Host "Extracting lldb into $Prefix\bin ..."
    $binDir = Join-Path $Prefix 'bin'
    # lldb-instr/lldb-mcp are omitted: 60 MB of tooling nothing here uses.
    & $sevenZip e -o"$binDir" $installer `
        'bin/lldb.exe' 'bin/lldb-dap.exe' 'bin/lldb-argdumper.exe' `
        'bin/lldb-server.exe' 'bin/liblldb.dll' -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "failed to extract lldb from $installer" }

    if (-not (Test-Path (Join-Path $binDir $LldbPythonDll))) {
        $pythonAsset = "python-$LldbPythonVersion-embed-amd64.zip"
        $pythonZip = Join-Path $CacheDir $pythonAsset
        Get-Download `
            -Uri "https://www.python.org/ftp/python/$LldbPythonVersion/$pythonAsset" `
            -Destination $pythonZip `
            -Label "$pythonAsset (~11 MB, liblldb's Python runtime)"

        Write-Host "Extracting $LldbPythonDll next to lldb.exe ..."
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($LldbPythonDll)
        & $sevenZip e -o"$binDir" $pythonZip $LldbPythonDll "$stem.zip" -y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "failed to extract $LldbPythonDll from $pythonZip" }
    }

    $reported = (& $lldb --version 2>&1 | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $reported) {
        throw "lldb was installed but does not run: $reported"
    }
    Write-Host "Installed $reported"
}

if ((Test-LlvmPrefix $Prefix) -and -not $Force) {
    Write-Host "LLVM $LlvmVersion already installed at $Prefix"
} else {
    Get-Download -Uri $Url -Destination $Archive -Label "$Asset (~822 MB)"

    Write-Host "Extracting to $Prefix ..."
    if (Test-Path $Prefix) { Remove-Item -Recurse -Force $Prefix }
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    # The tarball has a single `clang+llvm-...` top-level dir; --strip-components
    # lands its contents directly in $Prefix.
    #
    # Resolved absolutely rather than through PATH: when this script is invoked
    # from Git bash, `tar.exe` finds GNU tar, which reads the `C:` in a Windows
    # path as a remote host ("Cannot connect to C: resolve failed"). Windows'
    # own bsdtar handles drive letters and xz.
    & $script:WindowsTar -xf $Archive -C $Prefix --strip-components=1
    if ($LASTEXITCODE -ne 0) { throw "extraction failed: $Archive" }

    if (-not (Test-LlvmPrefix $Prefix)) {
        throw "extracted tree at $Prefix is missing bin\llvm-config.exe, lib\LLVM-C.lib or bin\LLVM-C.dll"
    }
    Write-Host "Installed LLVM $LlvmVersion to $Prefix"
}

if ($DevTools) {
    Install-DevTools
} else {
    Write-Host "Skipping debugger install; re-run with -DevTools (or PEPPER_SETUP_DEVTOOLS=1) to add lldb."
}

# Point cargo at the prefix. `.cargo/config.toml` [env] reaches build scripts,
# so llvm-sys sees it with no shell state -- `cargo build` just works.
$CargoDir = Join-Path $RepoRoot '.cargo'
New-Item -ItemType Directory -Force -Path $CargoDir | Out-Null
$CargoConfig = Join-Path $CargoDir 'config.toml'
$EscapedPrefix = $Prefix -replace '\\', '\\'
@"
# Generated by scripts/setup-llvm.ps1 -- do not edit, do not commit.
# The path is machine-specific; re-run the script on a new machine.
[env]
LLVM_SYS_${LlvmSysMajor}_PREFIX = "$EscapedPrefix"
"@ | Set-Content -Path $CargoConfig -Encoding utf8

Write-Host "Wrote $CargoConfig (LLVM_SYS_${LlvmSysMajor}_PREFIX)"
Write-Host "Run 'cargo build' to verify."
