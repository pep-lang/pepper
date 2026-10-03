<#
.SYNOPSIS
    Installs Pepper on Windows from a release's prebuilt archive.

.DESCRIPTION
    Downloads pepper-<version>-windows-x64.zip (the newest release that has
    one, or -Version's), checks it against its .sha256, unpacks it into
    %LOCALAPPDATA%\pepper (bin\ and runtime\), and adds its bin folder to the
    user's PATH. Running it again replaces the install; -Uninstall removes it
    and the PATH entry.

    Linking a program needs clang and the MSVC libraries and Windows SDK.
    When there is no clang it offers to install LLVM with Scoop, winget or
    Chocolatey, whichever is present, else with LLVM's own installer from
    its GitHub release; when there are no MSVC build tools it offers to
    install the Visual Studio Build Tools' C++ workload with winget. It asks
    first unless -Yes is given. Last, it builds and runs a small program to
    show the install works, and fails if it cannot.

    Piped into PowerShell (irm ... | iex) it takes no parameters; set
    PEPPER_VERSION and PEPPER_HOME instead. GITHUB_TOKEN or GH_TOKEN, when
    set, is the token to download with while the repository is private.

.PARAMETER Version
    Install this release (x.y.z) instead of the newest.

.PARAMETER Archive
    Install this downloaded archive instead of downloading one; it is
    checked against <Archive>.sha256 beside it.

.PARAMETER Prefix
    Install into this folder instead of $env:PEPPER_HOME, else
    %LOCALAPPDATA%\pepper.

.PARAMETER Yes
    Install missing prerequisites and change the PATH without asking.

.PARAMETER NoModifyPath
    Leave the user's PATH alone.

.PARAMETER NoPrerequisites
    Neither check for nor install LLVM and the MSVC build tools.

.PARAMETER Uninstall
    Remove the install and its PATH entry.

.EXAMPLE
    irm https://raw.githubusercontent.com/justinboswell/pepper/main/scripts/install.ps1 | iex

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

$Repo = 'justinboswell/pepper'
$Target = 'windows-x64'
# The LLVM installer to fall back on: the major pep-build is built against.
$LlvmVersion = '20.1.8'
$Token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $env:GH_TOKEN }

function Say([string]$Message) { Write-Host "pepper-install: $Message" }
function Warn([string]$Message) { Write-Warning "pepper-install: $Message" }
function Fail([string]$Message) { throw "pepper-install: $Message" }

# Asks a yes/no question; yes with -Yes.
function Ask([string]$Question) {
    if ($Yes) { return $true }
    $answer = Read-Host "pepper-install: $Question [Y/n]"
    return ($answer -eq '' -or $answer -match '^(y|yes)$')
}

# Downloads $Uri to $OutFile, with the token when there is one; the API
# serves a release asset's bytes for Accept: application/octet-stream.
function Get-Url([string]$Uri, [string]$OutFile, [string]$Accept = '*/*') {
    $headers = @{ Accept = $Accept; 'User-Agent' = 'pepper-install' }
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile -Headers $headers
}

# The release to install: the newest v<x.y.z> one, or -Version's, with this
# target's archive. The repository also has vsix-* and llvm-* releases.
function Find-Release([string]$Work) {
    $list = Join-Path $Work 'releases.json'
    try {
        Get-Url "https://api.github.com/repos/$Repo/releases?per_page=100" $list
    } catch {
        if (-not $Token) { Warn 'while the repository is private, set GITHUB_TOKEN to a token that can read it' }
        Fail "cannot list the releases of ${Repo}: $_"
    }
    $releases = Get-Content -Raw $list | ConvertFrom-Json
    foreach ($release in $releases) {
        if ($release.tag_name -notmatch '^v\d+\.\d+\.\d+') { continue }
        if ($Version -and $release.tag_name -ne "v$($Version.TrimStart('v'))") { continue }
        $name = "pepper-$($release.tag_name.Substring(1))-$Target.zip"
        $archive = $release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $archive) { continue }
        $checksum = $release.assets | Where-Object { $_.name -eq "$name.sha256" } | Select-Object -First 1
        if (-not $checksum) { Fail "release $($release.tag_name) has no $name.sha256 to check the download against" }
        return [pscustomobject]@{ Tag = $release.tag_name; Name = $name; Archive = $archive; Checksum = $checksum }
    }
    if ($Version) { Fail "release v$($Version.TrimStart('v')) has no pepper-$($Version.TrimStart('v'))-$Target.zip" }
    Fail "no release of $Repo has a prebuilt Pepper for $Target yet"
}

# Downloads a release asset: through the API with a token (a private
# repository's download links need one), else from its download link.
function Get-Asset($Asset, [string]$OutFile) {
    if ($Token) { Get-Url $Asset.url $OutFile 'application/octet-stream' }
    else { Get-Url $Asset.browser_download_url $OutFile }
}

function Get-UserPath { [Environment]::GetEnvironmentVariable('Path', 'User') }

function Set-UserPath([string]$Value) {
    [Environment]::SetEnvironmentVariable('Path', $Value, 'User')
}

function Test-OnPath([string]$Path, [string]$Folder) {
    return @($Path -split ';' | Where-Object { $_.TrimEnd('\') -ieq $Folder.TrimEnd('\') }).Count -gt 0
}

# A clang where pep-build looks for one (crates/pepper-driver/src/linker.rs):
# on the PATH, or in the folders LLVM's installers use.
function Find-Clang {
    $command = Get-Command clang.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($folder in @($env:ProgramFiles, $env:ProgramW6432, (Join-Path $env:USERPROFILE 'scoop\apps\llvm\current'))) {
        if (-not $folder) { continue }
        $candidate = if ($folder -like '*scoop*') { Join-Path $folder 'bin\clang.exe' } else { Join-Path $folder 'LLVM\bin\clang.exe' }
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

# Installs LLVM with the first package manager present, else with LLVM's
# own installer from its GitHub release.
function Install-Llvm([string]$Work) {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        if (Ask 'Install LLVM with "scoop install llvm"?') { scoop install llvm; return }
    } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        if (Ask 'Install LLVM with "winget install LLVM.LLVM"?') {
            winget install --id LLVM.LLVM --exact --accept-package-agreements --accept-source-agreements
            return
        }
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        if (Ask 'Install LLVM with "choco install llvm" (as administrator)?') {
            Start-Process choco -ArgumentList 'install', 'llvm', '-y' -Verb RunAs -Wait
            return
        }
    } else {
        $installer = "LLVM-$LlvmVersion-win64.exe"
        $url = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LlvmVersion/$installer"
        if (Ask "No Scoop, winget or Chocolatey found. Download and run LLVM's installer ($url)?") {
            $path = Join-Path $Work $installer
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $path
            # /S installs silently into Program Files; it asks for elevation.
            Start-Process $path -ArgumentList '/S' -Verb RunAs -Wait
            return
        }
    }
    Warn 'install LLVM before building a program: winget install LLVM.LLVM (or scoop install llvm, or choco install llvm)'
}

# Whether a Visual Studio or Build Tools install has the MSVC x64 tools,
# which carry the libraries (and with them the Windows SDK) clang links with.
function Test-MsvcTools {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $false }
    $found = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    return [bool]$found
}

function Install-MsvcTools {
    $workload = '--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    if ((Get-Command winget -ErrorAction SilentlyContinue) -and
        (Ask 'Linking needs the MSVC libraries and Windows SDK. Install the Visual Studio Build Tools C++ workload with winget?')) {
        winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --accept-package-agreements --accept-source-agreements --override $workload
        return
    }
    Warn 'install the Visual Studio Build Tools with the "Desktop development with C++" workload before building a program: https://visualstudio.microsoft.com/visual-cpp-build-tools/'
}

function Uninstall-Pepper {
    if (Test-Path $Prefix) {
        if (-not (Test-Path (Join-Path $Prefix 'bin\pep-build.exe'))) {
            Fail "$Prefix does not look like a Pepper install (no bin\pep-build.exe); remove it yourself"
        }
        Remove-Item -Recurse -Force $Prefix
        Say "removed $Prefix"
    } else {
        Say "nothing installed at $Prefix"
    }
    $bin = Join-Path $Prefix 'bin'
    $userPath = Get-UserPath
    if ($userPath -and (Test-OnPath $userPath $bin)) {
        Set-UserPath ((($userPath -split ';') | Where-Object { $_ -and $_.TrimEnd('\') -ine $bin.TrimEnd('\') }) -join ';')
        Say "removed $bin from your PATH"
    }
}

function Install-Pepper {
    if ([Environment]::Is64BitOperatingSystem -eq $false -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        Fail "there is no prebuilt Pepper for this processor yet; build it from source: https://github.com/$Repo#setting-up-a-development-environment"
    }
    $work = Join-Path ([IO.Path]::GetTempPath()) ("pepper-install-" + [Guid]::NewGuid())
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        if ($Archive) {
            if (-not (Test-Path $Archive)) { Fail "no archive at $Archive" }
            if (-not (Test-Path "$Archive.sha256")) { Fail "no $Archive.sha256 to check the archive against" }
            $name = Split-Path -Leaf $Archive
            $release = [pscustomobject]@{ Name = $name }
            $zip = Join-Path $work $name
            $sum = "$zip.sha256"
            Copy-Item $Archive $zip
            Copy-Item "$Archive.sha256" $sum
            Say "installing $name into $Prefix"
        } else {
            $release = Find-Release $work
            Say "installing Pepper $($release.Tag.Substring(1)) ($Target) into $Prefix"
            $zip = Join-Path $work $release.Name
            $sum = "$zip.sha256"
            Get-Asset $release.Archive $zip
            Get-Asset $release.Checksum $sum
        }
        $expected = ((Get-Content -Raw $sum).Trim() -split '\s+')[0]
        $actual = (Get-FileHash -Algorithm SHA256 $zip).Hash
        if ($expected -ine $actual) { Fail "$($release.Name) does not match its checksum (expected $expected, got $actual)" }

        Expand-Archive -Path $zip -DestinationPath $work
        $unpacked = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($release.Name))
        if (-not (Test-Path (Join-Path $unpacked 'bin\pep-build.exe'))) { Fail "$($release.Name) does not hold bin\pep-build.exe" }
        New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
        foreach ($entry in Get-ChildItem $unpacked) {
            $destination = Join-Path $Prefix $entry.Name
            if (Test-Path $destination) { Remove-Item -Recurse -Force $destination }
            Move-Item $entry.FullName $destination
        }
        # Files from the internet carry a mark that makes SmartScreen ask
        # before each one runs.
        Get-ChildItem -Recurse $Prefix | Unblock-File
        $bin = Join-Path $Prefix 'bin'
        Say "installed $(& (Join-Path $bin 'pepper.exe') --version)"

        if (-not (Test-OnPath $env:Path $bin)) {
            $userPath = Get-UserPath
            if ($NoModifyPath) {
                Say "add $bin to your PATH to run pepper"
            } elseif (Test-OnPath $userPath $bin) {
                Say 'open a new terminal to run pepper'
            } elseif (Ask "Add $bin to your PATH?") {
                Set-UserPath ((@($userPath -split ';' | Where-Object { $_ }) + $bin) -join ';')
                Say "added $bin to your PATH; open a new terminal to run pepper"
            } else {
                Say "add $bin to your PATH to run pepper"
            }
            $env:Path = "$env:Path;$bin"
        }

        if (-not $NoPrerequisites) {
            if (-not (Find-Clang)) {
                Say 'Linking programs needs clang (LLVM), which is not installed.'
                Install-Llvm $work
            }
            if (-not (Test-MsvcTools)) {
                Install-MsvcTools
            }
        }

        # Builds and runs a program with the new install, from an empty folder.
        $hello = Join-Path $work 'hello'
        New-Item -ItemType Directory -Path $hello | Out-Null
        Set-Content -Path (Join-Path $hello 'hello.pep') -Value "main(): int {`n    print(`"Pepper is installed.`");`n    return 0;`n}"
        Push-Location $hello
        try {
            & (Join-Path $bin 'pepper.exe') build hello.pep -o hello.exe
            if ($LASTEXITCODE -ne 0) { Fail "Pepper is installed in $Prefix, but could not build a program; see the error above" }
            & .\hello.exe
        } finally {
            Pop-Location
        }
    } finally {
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    }
}

if ($Uninstall) { Uninstall-Pepper } else { Install-Pepper }
