# Installs the newest release of the VS Code extension (pep-lang/vscode-pepper)
# into local VS Code.
#
#   scripts/install-vscode-extension.ps1
#
# The extension runs the `pep-lsp` of the installed toolchain (the one
# `pepper install which` names). To try a server built from this checkout,
# set `pepper.lspPath` to it: every rebuild
#
#   $env:PEPPER_RUNTIME = "$PWD/runtime"
#   pep-build -O tools/pep-lsp/main.pep -o target/pep-lsp/pep-lsp.exe
#
# then restarts the server with no install step at all.
param(
    # VS Code CLI; pass "code-insiders" to target Insiders.
    [string]$Code = "code"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Native commands don't throw on failure; check the exit code of each.
function Invoke-Native([scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "'$Command' failed with exit code $LASTEXITCODE" }
}

$release = Invoke-RestMethod "https://api.github.com/repos/pep-lang/vscode-pepper/releases/latest"
$asset = @($release.assets | Where-Object { $_.name -like "*.vsix" })[0]
if (-not $asset) { throw "release $($release.tag_name) of pep-lang/vscode-pepper has no .vsix" }
$vsix = Join-Path ([System.IO.Path]::GetTempPath()) $asset.name
Invoke-WebRequest $asset.browser_download_url -OutFile $vsix
Invoke-Native { & $Code --install-extension $vsix --force }
Write-Host "Installed $($asset.name) from pep-lang/vscode-pepper $($release.tag_name)."
