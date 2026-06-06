param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$configPath = Join-Path $ProjectPath 'app\src\main\assets\tracer\TemporalTracerConfig.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing tracer config: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$failures = New-Object System.Collections.Generic.List[string]

if ($config.schema -ne 'temporal-experience-tracer.config.v1') {
    $failures.Add("Unexpected schema: $($config.schema)")
}
if (-not $config.axis) {
    $failures.Add("Missing axis config")
}
if ([int]$config.axis.viewBoxWidth -le 0 -or [int]$config.axis.viewBoxHeight -le 0) {
    $failures.Add("Axis viewBox dimensions must be positive")
}
if ([int]$config.axis.targetSampleCount -lt 2) {
    $failures.Add("targetSampleCount must be >= 2")
}
if (@($config.axis.horizontalGridLabels).Count -lt 2) {
    $failures.Add("Need at least two horizontal grid labels")
}
if (@($config.axis.verticalGridLabels).Count -lt 2) {
    $failures.Add("Need at least two vertical grid labels")
}

foreach ($language in @('English', 'Deutsch')) {
    $items = @($config.items.$language)
    if ($items.Count -lt 2) {
        $failures.Add("$language has too few tracer items: $($items.Count)")
    }
    foreach ($item in $items) {
        if ([string]::IsNullOrWhiteSpace($item.label) -or [string]::IsNullOrWhiteSpace($item.message)) {
            $failures.Add("$language has an item with missing label/message")
        }
    }
}

$englishAudioDir = Join-Path $ProjectPath 'app\src\main\assets\tracer\audio\English'
if (-not (Test-Path -LiteralPath $englishAudioDir)) {
    $failures.Add("Missing English audio directory: $englishAudioDir")
}
else {
    $englishAudio = @(Get-ChildItem -LiteralPath $englishAudioDir -Filter '*.wav' -File)
    $englishItems = @($config.items.English)
    if ($englishAudio.Count -lt $englishItems.Count) {
        $failures.Add("English audio count too low: $($englishAudio.Count), expected at least $($englishItems.Count)")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "Temporal tracer asset validation failed"
}

[pscustomobject]@{
    schema = $config.schema
    tracerId = $config.tracerId
    englishItems = @($config.items.English).Count
    germanItems = @($config.items.Deutsch).Count
    englishAudio = if (Test-Path -LiteralPath $englishAudioDir) { @(Get-ChildItem -LiteralPath $englishAudioDir -Filter '*.wav' -File).Count } else { 0 }
    horizontalGridLabels = @($config.axis.horizontalGridLabels).Count
    verticalGridLabels = @($config.axis.verticalGridLabels).Count
    targetSampleCount = [int]$config.axis.targetSampleCount
    viewBox = "$($config.axis.viewBoxWidth)x$($config.axis.viewBoxHeight)"
} | ConvertTo-Json -Depth 4
