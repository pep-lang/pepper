#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Build a minimal LLVM package for CI out of a full install prefix.

.DESCRIPTION
    The official release tree is 4.1 GB on Windows, 3.4 GB of it tools this
    project never invokes. What the build actually needs is:

      bin/llvm-config.exe   llvm-sys discovery
      lib/LLVM-C.lib        import library
      bin/LLVM-C.dll        the LLVM implementation (Windows links the DLL --
                            see crates/pepper-codegen/build.rs for why; pepc,
                            through pepper-llvm, links it too)
      bin/clang.exe         link driver (tools/compiler/driver/linker.pep,
                            crates/pepper-driver/src/linker.rs)

    That is roughly 175 MB. clang is kept here, unlike the Unix package, because
    a windows-latest runner has no clang of its own to fall back to.

.PARAMETER Prefix
    Full LLVM install to take the pieces from.

.PARAMETER Output
    Path of the .tar.xz to write.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Prefix,
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'

$required = @(
    'bin\llvm-config.exe',
    'bin\LLVM-C.dll',
    'bin\clang.exe',
    'lib\LLVM-C.lib'
)

foreach ($item in $required) {
    if (-not (Test-Path (Join-Path $Prefix $item))) {
        throw "$Prefix is missing $item"
    }
}

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("llvm-pkg-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path (Join-Path $staging 'bin') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $staging 'lib') | Out-Null

try {
    foreach ($item in $required) {
        Copy-Item (Join-Path $Prefix $item) (Join-Path $staging $item) -Force
    }

    # llvm-sys's build script runs `llvm-config --libs`, and llvm-config fails
    # outright ("component libraries and shared library") unless every
    # component .lib it would name is present -- even though Windows links
    # LLVM-C.dll and never consumes these archives. 145 files, ~277 MB.
    $components = Get-ChildItem (Join-Path $Prefix 'lib') -Filter 'LLVM*.lib'
    if ($components.Count -eq 0) { throw "no LLVM*.lib component libraries in $Prefix\lib" }
    Copy-Item $components.FullName (Join-Path $staging 'lib') -Force
    Write-Host ("  component libraries: {0}" -f $components.Count)

    # llvm-sys also compiles a small C shim (wrappers/*.c) against the C API,
    # so the C headers have to travel with the package: llvm-c itself plus
    # llvm/Config, which llvm-c/Target.h pulls in for the target .def lists.
    # ~2 MB of the 78 MB include tree; the C++ headers are not needed.
    foreach ($headers in @('include\llvm-c', 'include\llvm\Config')) {
        $source = Join-Path $Prefix $headers
        if (-not (Test-Path $source)) { throw "$Prefix is missing $headers" }
        $destination = Join-Path $staging $headers
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item $source $destination -Recurse -Force
    }

    $staged = (Get-ChildItem -Recurse -File $staging | Measure-Object -Sum Length).Sum / 1MB
    Write-Host ("  staged: {0:N0} MB" -f $staged)

    $outDir = Split-Path -Parent $Output
    if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

    # Windows' bundled bsdtar, resolved absolutely rather than through PATH:
    # invoked from Git bash, `tar.exe` finds GNU tar, which reads the `C:` of a
    # Windows path as a remote host and fails.
    $windowsTar = Join-Path $env:SystemRoot 'System32\tar.exe'
    & $windowsTar -C $staging -cJf $Output .
    if ($LASTEXITCODE -ne 0) { throw "tar failed for $Output" }

    $size = (Get-Item $Output).Length / 1MB
    Write-Host ("  package: {0:N0} MB" -f $size)
} finally {
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
}
