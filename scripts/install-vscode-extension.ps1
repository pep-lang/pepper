# Builds pep-lsp and the vscode-pepper extension from the current checkout
# (any branch, merged or not) and installs the result into local VS Code.
#
#   scripts/install-vscode-extension.ps1          # build and install once
#   scripts/install-vscode-extension.ps1 -Watch   # keep following the branch
#
# -Watch polls the branch's upstream, fast-forwards when it moves, and
# reinstalls when the LSP or extension sources changed. The running extension
# restarts its language server on its own once the new build lands; a change
# to the extension's own code still needs "Developer: Reload Window".
#
# The server is tools/pep-lsp, built with the installed toolchain's
# pep-build (the one `pepper install which` names, else the pep-build on the
# PATH) against this checkout's runtime, into target/pep-lsp/.
#
# For a tighter loop while editing the server, set `pepper.lspPath` to
# target/pep-lsp/pep-lsp.exe instead: every rebuild
#
#   $env:PEPPER_RUNTIME = "$PWD/runtime"
#   pep-build -O tools/pep-lsp/main.pep -o target/pep-lsp/pep-lsp.exe
#
# then restarts the server with no install step at all.
param(
    [switch]$Watch,
    [int]$IntervalSeconds = 60,
    # VS Code CLI; pass "code-insiders" to target Insiders.
    [string]$Code = "code"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$ext = Join-Path $repo "tools/vscode-pepper"
# Sources the vsix is built from.
# The server reads the Pepper front end (tools/compiler) and the runtime.
$sources = @("tools/pep-lsp", "tools/compiler", "runtime", "tools/vscode-pepper")

# Native commands don't throw on failure; check the exit code of each.
function Invoke-Native([scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "'$Command' failed with exit code $LASTEXITCODE" }
}

# The pep-build to build the server with: the installed toolchain's, else
# the one on the PATH.
function Find-PepBuild {
    $pepper = Get-Command pepper -ErrorAction SilentlyContinue
    if ($pepper) {
        $which = & $pepper.Source install which 2>$null
        if ($LASTEXITCODE -eq 0 -and @($which).Count -ge 2 -and (Test-Path $which[1])) { return $which[1] }
    }
    $pepBuild = Get-Command pep-build -ErrorAction SilentlyContinue
    if ($pepBuild) { return $pepBuild.Source }
    throw "no pep-build: install the Pepper toolchain (scripts/install.ps1) or put a pep-build on the PATH"
}

function Install-PepperExtension {
    Push-Location $repo
    try {
        $pepBuild = Find-PepBuild
        $out = Join-Path $repo "target/pep-lsp"
        New-Item -ItemType Directory -Force $out | Out-Null
        $env:PEPPER_RUNTIME = Join-Path $repo "runtime"
        Invoke-Native { & $pepBuild -O --lto=full tools/pep-lsp/main.pep -o (Join-Path $out "pep-lsp.exe") --build (Join-Path $out "build") }

        # The extension looks for server/<platform>-<arch>/ matching the VS Code
        # process, which follows the OS architecture.
        $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        $target = if ($arch -eq "Arm64") { "win32-arm64" } else { "win32-x64" }
        $serverDir = Join-Path $ext "server/$target"
        New-Item -ItemType Directory -Force $serverDir | Out-Null
        Copy-Item (Join-Path $out "pep-lsp.exe") $serverDir -Force

        Push-Location $ext
        try {
            Invoke-Native { npm ci --no-audit --no-fund }
            # vsce wants the license beside package.json.
            Copy-Item (Join-Path $repo "LICENSE.md") (Join-Path $ext "LICENSE.md") -Force
            $vsix = Join-Path ([System.IO.Path]::GetTempPath()) "pepper-language-dev.vsix"
            Invoke-Native { npx --yes "@vscode/vsce@3" package --out $vsix }
        } finally { Pop-Location }

        Invoke-Native { & $Code --install-extension $vsix --force }
        Write-Host "Installed pepper-language from $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)."
    } finally { Pop-Location }
}

Install-PepperExtension
if (-not $Watch) { exit 0 }

Push-Location $repo
try {
    Invoke-Native { git rev-parse --abbrev-ref "@{u}" } | Out-Null  # needs an upstream to follow
    Write-Host "Watching upstream every $IntervalSeconds s; Ctrl+C to stop."
    while ($true) {
        Start-Sleep -Seconds $IntervalSeconds
        try {
            Invoke-Native { git fetch --quiet }
            $head = git rev-parse HEAD
            $upstream = git rev-parse "@{u}"
            if ($head -eq $upstream) { continue }
            Invoke-Native { git merge --ff-only --quiet "@{u}" }
            git diff --quiet $head $upstream -- @sources
            if ($LASTEXITCODE -ne 0) { Install-PepperExtension }
        } catch {
            # A dirty tree, diverged branch or offline fetch: report, keep going.
            Write-Warning $_
        }
    }
} finally { Pop-Location }
