param(
    [string]$MoonHome = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$oldMoonHome = $env:MOON_HOME
$oldMooncOverride = $env:MOONC_OVERRIDE
$oldPath = $env:PATH
Push-Location $projectRoot
try {
    if ($MoonHome) {
        if (-not (Test-Path -LiteralPath "$MoonHome\bin\moon.exe")) { throw 'MoonBit toolchain not found at -MoonHome.' }
        $env:MOON_HOME = $MoonHome
        $env:MOONC_OVERRIDE = "$MoonHome\bin\moonc.exe"
        $env:PATH = "$MoonHome\bin;$env:PATH"
        $moon = "$MoonHome\bin\moon.exe"
    } else {
        $moonCommand = Get-Command moon -ErrorAction SilentlyContinue
        if ($null -eq $moonCommand) { throw 'MoonBit toolchain not found in PATH; install it or pass -MoonHome.' }
        $moon = $moonCommand.Source
    }

    Write-Output '1/4 Explain where compiler flags come from'
    & $moon run --target native cmd/query examples/valid imagekit --cflags --explain
    if ($LASTEXITCODE -ne 0) { throw 'Explain query failed.' }

    Write-Output '2/4 Check that invalid metadata is rejected with diagnostics'
    $invalidOutput = (& $moon run --target native cmd/check examples/invalid 2>&1 | Out-String).Trim()
    Write-Output $invalidOutput
    if ($LASTEXITCODE -ne 1 -or $invalidOutput -notmatch '4 diagnostics\.') { throw 'Invalid directory check did not behave as expected.' }

    Write-Output '3/4 Apply an explicit cross-compilation sysroot'
    $sysrootOutput = (& $moon run --target native cmd/query examples/path-policy paths --cflags --sysroot=/sdk | Out-String).Trim()
    Write-Output $sysrootOutput
    if ($LASTEXITCODE -ne 0 -or $sysrootOutput -ne '-I/sdk/usr/include -I/sdk/opt/include -isystem /sdk/usr/include/system -DKEEP=1') { throw 'Sysroot query differs.' }

    Write-Output '4/4 Resolve and reject two versioned virtual dependencies'
    & $moon run --target native cmd/query examples/provides bar-new --path testdata/pkgconf-3.0.7 --exists
    if ($LASTEXITCODE -ne 0) { throw 'Matching virtual dependency was rejected.' }
    & $moon run --target native cmd/query examples/provides bar-old --path testdata/pkgconf-3.0.7 --exists *> $null
    if ($LASTEXITCODE -ne 1) { throw 'Incompatible virtual dependency was accepted.' }

    Write-Output 'Reviewer walkthrough: passed'
    $global:LASTEXITCODE = 0
} finally {
    Pop-Location
    $env:MOON_HOME = $oldMoonHome
    $env:MOONC_OVERRIDE = $oldMooncOverride
    $env:PATH = $oldPath
}
