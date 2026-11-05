# Jellyfin Desktop - installs the release Qt WebEngine 6.12.0 package into a Qt install
#
# aqt (and install-qt-action) install a stale pre-release Qt WebEngine for Qt 6.12.0 that does
# not load with the release qtbase, so the release package is installed from download.qt.io.
#
# Usage: powershell -ExecutionPolicy Bypass -File qtwebengine-release.ps1 -QtDir <Qt>\6.12.0\msvc2022_64

param(
    [Parameter(Mandatory = $true)][string]$QtDir,
    [string]$SevenZip = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$WebEngineUrl = "https://download.qt.io/online/qtsdkrepository/windows_x86/extensions/qtwebengine/6120/61400/msvc2022_64/extensions.qtwebengine.6120.61400.win64_msvc2022_64/6.12.0-0-202609281005qtwebengine-Windows-Windows_11_24H2-MSVC2022-Windows-Windows_11_24H2-X86_64.7z"
$WebEngineSha256 = "3b3b1fe362d6d20e97a8201c9bd2a7921f4de481cc0f3b919fcdd6f810557b18"

function Get-VerifiedFile([string]$Url, [string]$Path, [string]$Sha256) {
    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing
    $actual = (Get-FileHash -Algorithm SHA256 $Path).Hash
    if ($actual -ne $Sha256) {
        throw "SHA-256 mismatch for ${Url}: expected $Sha256, got $actual"
    }
}

if (-not (Test-Path (Join-Path $QtDir "bin\Qt6Core.dll"))) {
    throw "$QtDir does not look like a Qt install (bin\Qt6Core.dll not found)"
}
if (-not $SevenZip) {
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    $SevenZip = if ($cmd) { $cmd.Source } else { "C:\Program Files\7-Zip\7z.exe" }
}
if (-not (Test-Path $SevenZip)) {
    throw "7-Zip not found ($SevenZip)"
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("qtwebengine-release-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $webEngine = Join-Path $tmp "qtwebengine.7z"
    Get-VerifiedFile $WebEngineUrl $webEngine $WebEngineSha256
    Write-Host "Installing release Qt WebEngine 6.12.0 into $QtDir"
    & $SevenZip x $webEngine "-o$QtDir" -y -bso0 -bsp0
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract $webEngine" }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
