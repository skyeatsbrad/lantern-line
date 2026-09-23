param(
    [string]$GodotPath = "$env:USERPROFILE\Tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe",
    [int]$Runs = 3,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "design\audits\v0.8-baseline.md"
}
if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}
if ($Runs -lt 1) {
    throw "Runs must be at least one."
}

$scenarios = @(
    [ordered]@{ Name = "Desktop gameplay"; Slug = "gameplay"; Dense = $false; Audio = $false },
    [ordered]@{ Name = "Dense combat"; Slug = "dense"; Dense = $true; Audio = $false },
    [ordered]@{ Name = "Audio stress"; Slug = "audio"; Dense = $false; Audio = $true }
)

$allResults = @()

function Invoke-LanternProbe {
    param(
        [System.Collections.IDictionary]$Scenario,
        [int]$RunNumber
    )

    $savedProbe = $env:LANTERN_PROBE
    $savedDense = $env:LANTERN_PROBE_DENSE_COMBAT
    $savedAudio = $env:LANTERN_PROBE_AUDIO
    $savedWarmup = $env:LANTERN_METRICS_WARMUP
    try {
        $env:LANTERN_PROBE = "1"
        $env:LANTERN_METRICS_WARMUP = "2"
        if ($Scenario.Dense) {
            $env:LANTERN_PROBE_DENSE_COMBAT = "1"
        } else {
            Remove-Item Env:LANTERN_PROBE_DENSE_COMBAT -ErrorAction SilentlyContinue
        }
        if ($Scenario.Audio) {
            $env:LANTERN_PROBE_AUDIO = "1"
        } else {
            Remove-Item Env:LANTERN_PROBE_AUDIO -ErrorAction SilentlyContinue
        }

        Write-Host "[baseline] $($Scenario.Name) run $RunNumber/$Runs"
        $output = @(
            & $GodotPath --path $repoRoot --windowed --resolution 1280x720 2>&1
        )
        $exitCode = $LASTEXITCODE
        $outputText = $output -join [Environment]::NewLine
        if ($exitCode -ne 0) {
            throw "Probe failed ($exitCode):`n$outputText"
        }
        if ($outputText -match "SCRIPT ERROR|Parse Error|ERROR:") {
            throw "Probe emitted an engine error:`n$outputText"
        }
        $jsonLine = $output |
            Where-Object { "$_" -match "^\[probe\] presentation_json " } |
            Select-Object -Last 1
        if ($null -eq $jsonLine) {
            throw "Probe did not emit presentation JSON:`n$outputText"
        }
        $json = ("$jsonLine" -replace "^\[probe\] presentation_json ", "")
        $metrics = $json | ConvertFrom-Json
        if ($metrics.warming_up) {
            throw "Probe ended before the warm-up period completed."
        }
        return [pscustomobject]@{
            Scenario = $Scenario.Name
            Slug = $Scenario.Slug
            Run = $RunNumber
            Metrics = $metrics
        }
    }
    finally {
        if ($null -eq $savedProbe) {
            Remove-Item Env:LANTERN_PROBE -ErrorAction SilentlyContinue
        } else {
            $env:LANTERN_PROBE = $savedProbe
        }
        if ($null -eq $savedDense) {
            Remove-Item Env:LANTERN_PROBE_DENSE_COMBAT -ErrorAction SilentlyContinue
        } else {
            $env:LANTERN_PROBE_DENSE_COMBAT = $savedDense
        }
        if ($null -eq $savedAudio) {
            Remove-Item Env:LANTERN_PROBE_AUDIO -ErrorAction SilentlyContinue
        } else {
            $env:LANTERN_PROBE_AUDIO = $savedAudio
        }
        if ($null -eq $savedWarmup) {
            Remove-Item Env:LANTERN_METRICS_WARMUP -ErrorAction SilentlyContinue
        } else {
            $env:LANTERN_METRICS_WARMUP = $savedWarmup
        }
    }
}

foreach ($scenario in $scenarios) {
    for ($run = 1; $run -le $Runs; $run++) {
        $allResults += Invoke-LanternProbe -Scenario $scenario -RunNumber $run
    }
}

function Average-Field {
    param(
        [object[]]$Rows,
        [string]$Field
    )
    return [double](($Rows | ForEach-Object {
        [double]$_.Metrics.$Field
    } | Measure-Object -Average).Average)
}

function Range-Field {
    param(
        [object[]]$Rows,
        [string]$Field
    )
    $measure = $Rows | ForEach-Object {
        [double]$_.Metrics.$Field
    } | Measure-Object -Minimum -Maximum
    return "{0:N2}-{1:N2}" -f $measure.Minimum, $measure.Maximum
}

$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$fingerprintScript = Join-Path $PSScriptRoot "source_fingerprint.py"
$fingerprintJson = (& python $fingerprintScript --repo $repoRoot) -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0) {
    throw "Source fingerprint generation failed."
}
$fingerprint = $fingerprintJson | ConvertFrom-Json
$publicPckPath = Join-Path $repoRoot "docs\index.pck"
$publicPckBytes = if (Test-Path -LiteralPath $publicPckPath) {
    (Get-Item -LiteralPath $publicPckPath).Length
} else {
    0
}
$localPckPath = Join-Path $repoRoot "build\web\index.pck"
$localPckBytes = if (Test-Path -LiteralPath $localPckPath) {
    (Get-Item -LiteralPath $localPckPath).Length
} else {
    0
}

$lines = @(
    "# v0.8 Warm Performance Baseline",
    "",
    "Date: $(Get-Date -Format 'yyyy-MM-dd')",
    "",
    "Commit: ``$commit``",
    "",
    "Source fingerprint: ``$($fingerprint.source_fingerprint)``",
    "",
    "Protocol:",
    "",
    "- Godot 4.7.2 Compatibility renderer.",
    "- 1280 x 720 window.",
    "- Two-second warm-up excluded.",
    "- $Runs measured runs per scenario.",
    "- Metrics are sampled after scene construction and reported from recorded frames only.",
    "- Committed v0.7 ``docs/index.pck``: $publicPckBytes bytes.",
    "- Local M0 ``build/web/index.pck``: $localPckBytes bytes.",
    "",
    "| Scenario | FPS | Frame p50 | Frame p95 | Frame p99 | Frame max | Draw avg | Draw p95 | Draw max | Texture MiB |",
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
)

foreach ($scenario in $scenarios) {
    $rows = @($allResults | Where-Object { $_.Slug -eq $scenario.Slug })
    $lines += (
        "| {0} | {1:N1} | {2:N2} ms | {3:N2} ms | {4:N2} ms | {5:N2} ms | {6:N1} | {7:N1} | {8:N0} | {9:N1} |" -f
        $scenario.Name,
        (Average-Field $rows "fps"),
        (Average-Field $rows "frame_p50_ms"),
        (Average-Field $rows "frame_p95_ms"),
        (Average-Field $rows "frame_p99_ms"),
        (Average-Field $rows "worst_frame_ms"),
        (Average-Field $rows "draw_calls_average"),
        (Average-Field $rows "draw_calls_p95"),
        (Average-Field $rows "draw_calls_max"),
        (Average-Field $rows "texture_memory_mib")
    )
}

$lines += @(
    "",
    "## Run ranges",
    "",
    "| Scenario | p95 frame range | p95 draw range | Recorded-frame range |",
    "|---|---:|---:|---:|"
)
foreach ($scenario in $scenarios) {
    $rows = @($allResults | Where-Object { $_.Slug -eq $scenario.Slug })
    $lines += (
        "| {0} | {1} ms | {2} | {3} |" -f
        $scenario.Name,
        (Range-Field $rows "frame_p95_ms"),
        (Range-Field $rows "draw_calls_p95"),
        (Range-Field $rows "recorded_frames")
    )
}

$lines += @(
    "",
    "## Gate rule",
    "",
    "M3-M7 compare against these warm values. During migration, matching draw-call p95 may not exceed this baseline by more than 10%. The final optimization target is at least 15% below the matching baseline.",
    ""
)

New-Item -ItemType Directory -Path (Split-Path $OutputPath) -Force | Out-Null
$lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[baseline] wrote $OutputPath"
