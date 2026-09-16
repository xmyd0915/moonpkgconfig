param(
    [string]$MoonHome = 'C:\Users\hp\Documents\Codex\2026-09-16\new-chat\work\moonbit-toolchain\portable'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$oldMoonHome = $env:MOON_HOME
$oldMooncOverride = $env:MOONC_OVERRIDE
$oldPath = $env:PATH
Push-Location $projectRoot
try {
    if (-not (Test-Path -LiteralPath "$MoonHome\bin\moon.exe")) { throw 'MoonBit toolchain not found; pass -MoonHome.' }
    $env:MOON_HOME = $MoonHome
    $env:MOONC_OVERRIDE = "$MoonHome\bin\moonc.exe"
    $env:PATH = "$MoonHome\bin;$env:PATH"
    & "$MoonHome\bin\moon.exe" fmt
    if ($LASTEXITCODE -ne 0) { throw 'Formatting failed.' }
    & "$MoonHome\bin\moon.exe" check --target all --deny-warn
    if ($LASTEXITCODE -ne 0) { throw 'Type checking failed.' }
    & "$MoonHome\bin\moon.exe" test --target all --deny-warn
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    & "$MoonHome\bin\moon.exe" run cmd/demo
    if ($LASTEXITCODE -ne 0) { throw 'Demo failed.' }
} finally {
    Pop-Location
    $env:MOON_HOME = $oldMoonHome
    $env:MOONC_OVERRIDE = $oldMooncOverride
    $env:PATH = $oldPath
}
