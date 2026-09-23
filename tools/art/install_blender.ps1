param(
    [string]$InstallRoot = "$env:USERPROFILE\Tools",
    [switch]$VerifyOnly,
    [switch]$SkipSmoke,
    [switch]$SkipPythonDependencies
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pinPath = Join-Path $PSScriptRoot "blender_pin.json"
$pin = Get-Content -LiteralPath $pinPath -Raw | ConvertFrom-Json
$installDirectory = Join-Path $InstallRoot ("Blender-" + $pin.version)
$blenderDirectory = Join-Path $installDirectory $pin.install_subdirectory
$blenderExe = Join-Path $blenderDirectory "blender.exe"
$archivePath = Join-Path $env:TEMP $pin.archive

if (-not (Test-Path -LiteralPath $blenderExe)) {
    if ($VerifyOnly) {
        throw "Pinned Blender is not installed at $blenderExe"
    }
    if (Test-Path -LiteralPath $installDirectory) {
        throw "Install directory exists without the pinned executable: $installDirectory"
    }
    if (-not (Test-Path -LiteralPath $archivePath)) {
        Write-Host "[blender] downloading $($pin.url)"
        Invoke-WebRequest -Uri $pin.url -OutFile $archivePath
    }
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $pin.sha256) {
        throw "Blender archive hash mismatch: expected $($pin.sha256), got $actualHash"
    }
    New-Item -ItemType Directory -Path $installDirectory | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $installDirectory
}

$versionLine = (& $blenderExe --version 2>&1 | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or $versionLine -notmatch [regex]::Escape($pin.version)) {
    throw "Pinned Blender version check failed: $versionLine"
}

$venvPython = Join-Path $repoRoot ".tools\v08-art-venv\Scripts\python.exe"
if (-not $SkipPythonDependencies) {
    if (-not (Test-Path -LiteralPath $venvPython)) {
        python -m venv (Join-Path $repoRoot ".tools\v08-art-venv")
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create the v0.8 art virtual environment."
        }
    }
    & $venvPython -m pip install --disable-pip-version-check --quiet `
        -r (Join-Path $PSScriptRoot "requirements.txt")
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install the pinned art dependencies."
    }
}

$smokeOutput = Join-Path $repoRoot "build\v08-toolchain\blender-smoke.png"
if (-not $SkipSmoke) {
    New-Item -ItemType Directory -Path (Split-Path $smokeOutput) -Force | Out-Null
    & $blenderExe --background --factory-startup `
        --python (Join-Path $PSScriptRoot "blender_smoke.py") `
        -- --output $smokeOutput
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $smokeOutput)) {
        throw "Blender headless smoke render failed."
    }
}

$receiptDirectory = Join-Path $repoRoot ".tools"
New-Item -ItemType Directory -Path $receiptDirectory -Force | Out-Null
$receipt = [ordered]@{
    version = $pin.version
    archive = $pin.archive
    url = $pin.url
    sha256 = $pin.sha256
    executable = $blenderExe
    version_output = [string]$versionLine
    smoke_output = if ($SkipSmoke) { "" } else { $smokeOutput }
    python = if ($SkipPythonDependencies) { "" } else { $venvPython }
}
$receipt | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $receiptDirectory "blender_install_receipt.json") -Encoding UTF8

Write-Host "[blender] verified $versionLine"
Write-Host "[blender] executable $blenderExe"
if (-not $SkipSmoke) {
    Write-Host "[blender] smoke $smokeOutput"
}
