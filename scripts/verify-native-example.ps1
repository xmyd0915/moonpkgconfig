$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $projectRoot 'examples/native/build'

Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

    & gcc -Iexamples/native/include -c examples/native/src/moonpkg_demo.c -o "$buildDir/moonpkg_demo.o"
    if ($LASTEXITCODE -ne 0) { throw 'C library compilation failed.' }
    & ar rcs "$buildDir/libmoonpkg_demo.a" "$buildDir/moonpkg_demo.o"
    if ($LASTEXITCODE -ne 0) { throw 'Static library creation failed.' }

    $cflags = (& moon run --target native cmd/query examples/native moonpkg-demo --cflags | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cflags query failed.' }
    $libs = (& moon run --target native cmd/query examples/native moonpkg-demo --libs | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Libs query failed.' }
    $arguments = @('-std=c++17', 'examples/native/demo.cpp') + ($cflags -split ' ') + ($libs -split ' ') + @('-o', "$buildDir/demo.exe")
    & g++ @arguments
    if ($LASTEXITCODE -ne 0) { throw 'C++ consumer compilation failed.' }

    $output = (& "$buildDir/demo.exe" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $output -ne 'MoonPkgConfig native demo: 42') { throw 'Native integration output mismatch.' }
    Write-Output 'Native C/C++ integration: passed'
} finally {
    Pop-Location
}
