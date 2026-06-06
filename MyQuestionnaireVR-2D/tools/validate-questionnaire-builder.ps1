param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$Node = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Test-NodeCandidate {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate) -or -not (Test-Path -LiteralPath $Candidate)) {
        return $false
    }

    try {
        $output = & $Candidate --version 2>&1
        return $LASTEXITCODE -eq 0 -and ($output -match '^v')
    }
    catch {
        return $false
    }
}

function Resolve-Node {
    param([string]$RequestedNode)

    if (-not [string]::IsNullOrWhiteSpace($RequestedNode)) {
        if (Test-NodeCandidate $RequestedNode) {
            return $RequestedNode
        }
        throw "Node runtime is not executable: $RequestedNode"
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $command = Get-Command node -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        $candidates.Add($command.Source) | Out-Null
    }

    $bundled = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
    $candidates.Add($bundled) | Out-Null

    foreach ($candidate in $candidates) {
        if (Test-NodeCandidate $candidate) {
            return $candidate
        }
    }

    throw "No working Node runtime found. Install Node.js/npm or pass -Node."
}

$nodePath = Resolve-Node -RequestedNode $Node
$testScript = Join-Path $ProjectPath 'tools\questionnaire-config-editor\builder-smoke-test.js'
if (-not (Test-Path -LiteralPath $testScript)) {
    throw "Builder smoke test not found: $testScript"
}

$nodeArgs = @($testScript)
if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $nodeArgs += @('--output-dir', $OutputDir)
}

& $nodePath @nodeArgs
if ($LASTEXITCODE -ne 0) {
    throw "Questionnaire builder smoke test failed."
}
