<#
.SYNOPSIS
    Installs Pepper on Windows from a release's prebuilt archive.

.DESCRIPTION
    Only bootstraps: downloads pepper-<version>-windows-x64.zip and the
    installer archive beside it, pepper-install-<version>-windows-x64.zip,
    from the newest release that has both (or -Version's), checks the
    installer against its .sha256, unpacks its pep-install.exe into a
    temporary folder and runs `pep-install setup --archive <toolchain
    archive>` with the options given. pep-install checks the toolchain
    archive, installs it into %LOCALAPPDATA%\pepper\toolchains\<version>,
    makes it the default, puts pepper.exe and pep-install.exe in
    %LOCALAPPDATA%\pepper\bin, adds that folder to the user's PATH, offers
    to install LLVM and the Visual Studio Build Tools' C++ workload, and
    builds a program to check (see docs/src/tools/pep-install.md).
    -Uninstall runs `pep-install uninstall`.

    Piped into PowerShell (irm ... | iex) it takes no parameters; set
    PEPPER_VERSION and PEPPER_HOME instead. GITHUB_TOKEN or GH_TOKEN, when
    set, is the token to download with while the repository is private.

.PARAMETER Version
    Install this release (x.y.z) instead of the newest.

.PARAMETER Archive
    Install this downloaded archive instead of downloading one; it is
    checked against <Archive>.sha256 beside it, and the installer archive
    pepper-install-<version>-windows-x64.zip must be beside it too.

.PARAMETER Prefix
    Install into this folder instead of $env:PEPPER_HOME, else
    %LOCALAPPDATA%\pepper.

.PARAMETER Yes
    Install missing prerequisites without asking.

.PARAMETER NoModifyPath
    Leave the user's PATH alone.

.PARAMETER NoPrerequisites
    Neither check for nor install LLVM and the MSVC build tools.

.PARAMETER Uninstall
    Remove the install and its PATH entry.

.EXAMPLE
    irm https://raw.githubusercontent.com/pep-lang/pepper/main/scripts/install.ps1 | iex

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1 -Version 0.4.0
#>
[CmdletBinding()]
param(
    [string]$Version = $env:PEPPER_VERSION,
    [string]$Archive,
    [string]$Prefix = $(if ($env:PEPPER_HOME) { $env:PEPPER_HOME } else { Join-Path $env:LOCALAPPDATA 'pepper' }),
    [switch]$Yes,
    [switch]$NoModifyPath,
    [switch]$NoPrerequisites,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
# Invoke-WebRequest's progress bar slows downloads tenfold on PowerShell 5.1.
$ProgressPreference = 'SilentlyContinue'
# PowerShell 5.1 offers TLS 1.0 by default, which GitHub refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Repo = 'pep-lang/pepper'
$Target = 'windows-x64'
$Token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $env:GH_TOKEN }

function Say([string]$Message) { Write-Host "pepper-install: $Message" }
function Warn([string]$Message) { Write-Warning "pepper-install: $Message" }
function Fail([string]$Message) { throw "pepper-install: $Message" }

# Downloads $Uri to $OutFile, with the token when there is one; the API
# serves a release asset's bytes for Accept: application/octet-stream.
function Get-Url([string]$Uri, [string]$OutFile, [string]$Accept = '*/*') {
    $headers = @{ Accept = $Accept; 'User-Agent' = 'pepper-install' }
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile -Headers $headers
}

# The release to install: the newest v<x.y.z> one, or -Version's, with this
# target's toolchain and installer archives. The repository also has
# vsix-* and llvm-* releases.
function Find-Release([string]$Work) {
    $list = Join-Path $Work 'releases.json'
    try {
        Get-Url "https://api.github.com/repos/$Repo/releases?per_page=100" $list
    } catch {
        if (-not $Token) { Warn 'while the repository is private, set GITHUB_TOKEN to a token that can read it' }
        Fail "cannot list the releases of ${Repo}: $_"
    }
    $wanted = if ($Version) { "v$($Version.TrimStart('v'))" } else { '' }
    $releases = Get-Content -Raw $list | ConvertFrom-Json
    foreach ($release in $releases) {
        if ($release.tag_name -notmatch '^v\d+\.\d+\.\d+') { continue }
        # A prerelease (v0.4.0-dev, the build of main) only when -Version names it.
        if ($release.tag_name.Contains('-') -and $release.tag_name -ne $wanted) { continue }
        if ($wanted -and $release.tag_name -ne $wanted) { continue }
        $number = $release.tag_name.Substring(1)
        $names = @("pepper-$number-$Target.zip", "pepper-install-$number-$Target.zip")
        $assets = @{}
        foreach ($name in $names + ($names | ForEach-Object { "$_.sha256" })) {
            $asset = $release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
            if ($asset) { $assets[$name] = $asset }
        }
        if (-not ($assets[$names[0]] -and $assets[$names[1]])) { continue }
        return [pscustomobject]@{ Tag = $release.tag_name; Names = $names; Assets = $assets }
    }
    if ($Version) { Fail "release $wanted has no pepper-$($wanted.Substring(1))-$Target.zip and pepper-install-$($wanted.Substring(1))-$Target.zip" }
    Fail "no release of $Repo has a prebuilt Pepper and its installer for $Target yet"
}

# Downloads the asset $Name of $Release, and its .sha256, into $Work:
# through the API with a token (a private repository's download links need
# one), else from its download link.
function Get-Asset($Release, [string]$Name, [string]$Work) {
    foreach ($file in $Name, "$Name.sha256") {
        $asset = $Release.Assets[$file]
        if (-not $asset) { Fail "release $($Release.Tag) has no $file" }
        $path = Join-Path $Work $file
        if ($Token) { Get-Url $asset.url $path 'application/octet-stream' }
        else { Get-Url $asset.browser_download_url $path }
    }
    return Join-Path $Work $Name
}

# Checks the installer archive against its .sha256 and unpacks its
# pep-install.exe into $Work\installer; returns its path.
function Expand-Installer([string]$Zip, [string]$Work) {
    if (-not (Test-Path "$Zip.sha256")) { Fail "no $Zip.sha256 to check the installer against" }
    $expected = ((Get-Content -Raw "$Zip.sha256").Trim() -split '\s+')[0]
    $actual = (Get-FileHash -Algorithm SHA256 $Zip).Hash
    if ($expected -ine $actual) { Fail "$(Split-Path -Leaf $Zip) does not match its checksum (expected $expected, got $actual)" }
    $folder = Join-Path $Work 'installer'
    Expand-Archive -Path $Zip -DestinationPath $folder
    $installer = Join-Path $folder 'pep-install.exe'
    if (-not (Test-Path $installer)) { Fail "$(Split-Path -Leaf $Zip) holds no pep-install.exe" }
    # Files from the internet carry a mark that makes SmartScreen ask
    # before each one runs.
    Unblock-File $installer
    return $installer
}

function Invoke-Installer([string]$Installer, [string[]]$Arguments) {
    & $Installer @Arguments
    if ($LASTEXITCODE -ne 0) { Fail "pep-install $($Arguments[0]) failed; see the error above" }
}

$env:PEPPER_HOME = $Prefix

# A home set up by pep-install uninstalls itself.
$homeInstaller = Join-Path $Prefix 'bin\pep-install.exe'
$knowsUninstall = $false
if ($Uninstall -and (Test-Path $homeInstaller)) {
    # An older pep-install has no uninstall; its error on stderr throws here.
    try { & $homeInstaller uninstall --help *> $null; $knowsUninstall = ($LASTEXITCODE -eq 0) } catch { }
}
if ($knowsUninstall) {
    # Copied out first: a running program cannot remove its own file.
    $copy = Join-Path ([IO.Path]::GetTempPath()) ("pep-install-" + [Guid]::NewGuid() + '.exe')
    Copy-Item $homeInstaller $copy
    try { Invoke-Installer $copy @('uninstall') } finally { Remove-Item -Force $copy -ErrorAction SilentlyContinue }
    return
}

if ([Environment]::Is64BitOperatingSystem -eq $false -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
    Fail "there is no prebuilt Pepper for this processor yet; build it from source: https://docs.pepper-lang.dev/dev/contributing/building.html"
}
$work = Join-Path ([IO.Path]::GetTempPath()) ("pepper-install-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    if ($Archive) {
        if (-not (Test-Path $Archive)) { Fail "no archive at $Archive" }
        $toolchain = (Resolve-Path $Archive).Path
        $installerZip = Join-Path (Split-Path -Parent $toolchain) ((Split-Path -Leaf $toolchain) -replace '^pepper-', 'pepper-install-')
        if (-not (Test-Path $installerZip)) { Fail "no installer archive $installerZip beside $toolchain" }
    } else {
        $release = Find-Release $work
        Say "downloading Pepper $($release.Tag.Substring(1)) ($Target)"
        $installerZip = Get-Asset $release $release.Names[1] $work
        if (-not $Uninstall) { $toolchain = Get-Asset $release $release.Names[0] $work }
    }
    $installer = Expand-Installer $installerZip $work
    if ($Uninstall) {
        Invoke-Installer $installer @('uninstall')
        return
    }
    $arguments = @('setup', '--archive', $toolchain)
    if ($Yes) { $arguments += '--yes' }
    if ($NoModifyPath) { $arguments += '--no-modify-path' }
    if ($NoPrerequisites) { $arguments += '--no-prerequisites' }
    Invoke-Installer $installer $arguments
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
