param(
    [string]$Python = "python",
    [string]$StreamName = "QuestChainControl",
    [string]$StreamType = "",
    [string]$Adb = "",
    [string]$Serial = "",
    [switch]$Once,
    [switch]$VerboseBridge,
    [switch]$KeepGoing,
    [switch]$InstallDependencies
)

$ErrorActionPreference = 'Stop'

if ($InstallDependencies) {
    & $Python -m pip install pylsl
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install pylsl."
    }
}

$script = Join-Path $PSScriptRoot 'lsl-chain-bridge.py'
$args = @($script, '--stream-name', $StreamName)
if (-not [string]::IsNullOrWhiteSpace($StreamType)) { $args += @('--stream-type', $StreamType) }
if (-not [string]::IsNullOrWhiteSpace($Adb)) { $args += @('--adb', $Adb) }
if (-not [string]::IsNullOrWhiteSpace($Serial)) { $args += @('--serial', $Serial) }
if ($Once) { $args += '--once' }
if ($VerboseBridge) { $args += '--verbose' }
if ($KeepGoing) { $args += '--keep-going' }

& $Python @args
if ($LASTEXITCODE -ne 0) {
    throw "LSL chain bridge exited with code $LASTEXITCODE."
}
