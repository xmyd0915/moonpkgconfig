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
    & "$MoonHome\bin\moon.exe" run --target native cmd/inspect examples/valid/imagekit.pc
    if ($LASTEXITCODE -ne 0) { throw 'File inspector failed.' }
    & "$MoonHome\bin\moon.exe" run --target native cmd/inspect examples/valid/imagekit.pc --json
    if ($LASTEXITCODE -ne 0) { throw 'JSON file inspector failed.' }
    & "$MoonHome\bin\moon.exe" run --target native cmd/inspect examples/invalid/broken.pc
    if ($LASTEXITCODE -ne 1) { throw 'Invalid file did not return diagnostic exit code 1.' }
    $cflags = (& "$MoonHome\bin\moon.exe" run --target native cmd/query examples/valid imagekit --cflags | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $cflags -ne '-I/opt/example/include/compression -I/opt/example/include/codec -I/opt/example/include -DIMAGEKIT=1') { throw 'Cflags query failed.' }
    $libs = (& "$MoonHome\bin\moon.exe" run --target native cmd/query examples/valid imagekit --libs | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $libs -ne '-L/opt/example/lib -limagekit -L/opt/example/lib -lcodec -L/opt/example/lib -lcompression') { throw 'Libs query failed.' }
    $staticLibs = (& "$MoonHome\bin\moon.exe" run --target native cmd/query examples/valid imagekit --libs --static | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $staticLibs -ne '-L/opt/example/lib -limagekit -lm -L/opt/example/lib -lcodec -L/opt/example/lib -lcompression -lz') { throw 'Static libs query failed.' }
    $deduplicatedLibs = (& "$MoonHome\bin\moon.exe" run --target native cmd/query examples/valid imagekit --libs --dedupe-paths | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $deduplicatedLibs -ne '-L/opt/example/lib -limagekit -lcodec -lcompression') { throw 'Search path deduplication failed.' }
    $validDirectory = (& "$MoonHome\bin\moon.exe" run --target native cmd/check examples/valid | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $validDirectory -ne 'Checked 3 packages from 3 .pc files; 0 diagnostics.') { throw 'Valid directory check failed.' }
    $invalidDirectory = (& "$MoonHome\bin\moon.exe" run --target native cmd/check examples/invalid | Out-String).Trim()
    if ($LASTEXITCODE -ne 1 -or $invalidDirectory -notmatch 'package-that-is-not-here' -or $invalidDirectory -notmatch 'private-helper' -or $invalidDirectory -notmatch '4 diagnostics\.') { throw 'Invalid directory check failed.' }
    $upstreamDirectory = (& "$MoonHome\bin\moon.exe" run --target native cmd/check testdata/pkgconf-3.0.7 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $upstreamDirectory -ne 'Checked 10 packages from 10 .pc files; 0 diagnostics.') { throw 'Upstream pkgconf corpus check failed.' }
} finally {
    Pop-Location
    $env:MOON_HOME = $oldMoonHome
    $env:MOONC_OVERRIDE = $oldMooncOverride
    $env:PATH = $oldPath
}
