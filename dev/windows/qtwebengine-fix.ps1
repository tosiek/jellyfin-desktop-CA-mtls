# Jellyfin Desktop - installs Qt WebEngine 6.12.0 with the WGL interop leak fix into a Qt install
#
# 1. aqt (and install-qt-action) install a stale pre-release Qt WebEngine for Qt 6.12.0 that does
#    not load with the release qtbase, so the release package is installed from download.qt.io.
# 2. Qt6WebEngineCore.dll and QtWebEngineProcess.exe are replaced with builds that include
#    0001-wgl-interop-texture-pool.patch. Without it, Qt Quick on OpenGL with AMD drivers leaks
#    the D3D11 texture of every web frame (several hundred MB per minute while the page changes),
#    because the driver does not free textures after wglDXUnregisterObjectNV.
#    Details and the patch: https://github.com/tosiek/qt-opengl-amd-leak
#
# Usage: powershell -ExecutionPolicy Bypass -File qtwebengine-fix.ps1 -QtDir <Qt>\6.12.0\msvc2022_64

param(
    [Parameter(Mandatory = $true)][string]$QtDir,
    [string]$SevenZip = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$WebEngineUrl = "https://download.qt.io/online/qtsdkrepository/windows_x86/extensions/qtwebengine/6120/61400/msvc2022_64/extensions.qtwebengine.6120.61400.win64_msvc2022_64/6.12.0-0-202609281005qtwebengine-Windows-Windows_11_24H2-MSVC2022-Windows-Windows_11_24H2-X86_64.7z"
$WebEngineSha256 = "3b3b1fe362d6d20e97a8201c9bd2a7921f4de481cc0f3b919fcdd6f810557b18"
$FixUrl = "https://github.com/tosiek/qt-opengl-amd-leak/releases/download/v3/qtwebengine-6.12.0-wgl-pool-win64.zip"
$FixSha256 = "d5e8e2811c587e6177de7e95047c1fc4552294e80069190b6399e322ab9a8bf1"
$FixFiles = @{
    "Qt6WebEngineCore.dll"   = "05582aa5cf412dc989e393a187a556bdf0c0789c48b6a48e30e39cea95d975f9"
    "QtWebEngineProcess.exe" = "ce2fc75d3042271f066b29bd3edceec02b67896e59cc5494c6c5c8ea58cbdc86"
}

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

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("qtwebengine-fix-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $webEngine = Join-Path $tmp "qtwebengine.7z"
    Get-VerifiedFile $WebEngineUrl $webEngine $WebEngineSha256
    Write-Host "Installing release Qt WebEngine 6.12.0 into $QtDir"
    & $SevenZip x $webEngine "-o$QtDir" -y -bso0 -bsp0
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract $webEngine" }

    $fix = Join-Path $tmp "fix.zip"
    Get-VerifiedFile $FixUrl $fix $FixSha256
    Expand-Archive -Path $fix -DestinationPath $tmp
    $fixDir = Join-Path $tmp "qtwebengine-6.12.0-wgl-pool-win64"
    foreach ($name in $FixFiles.Keys) {
        $src = Join-Path $fixDir $name
        if ((Get-FileHash -Algorithm SHA256 $src).Hash -ne $FixFiles[$name]) {
            throw "SHA-256 mismatch for $name"
        }
        Copy-Item -Force $src (Join-Path $QtDir "bin\$name")
        Write-Host "Installed patched $name"
    }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
