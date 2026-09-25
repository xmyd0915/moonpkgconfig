param(
    [string]$Reference = 'F:\jav\moonpkgconfig\.tools\pkgconf\extracted\PFiles64\pkgconf-3.0.7\pkgconf.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$oldPath = $env:PKG_CONFIG_PATH
$oldLibDir = $env:PKG_CONFIG_LIBDIR
$oldSysroot = $env:PKG_CONFIG_SYSROOT_DIR
$oldSystemIncludes = $env:PKG_CONFIG_SYSTEM_INCLUDE_PATH
$oldSystemLibraries = $env:PKG_CONFIG_SYSTEM_LIBRARY_PATH

function Invoke-Text([string]$Executable, [string[]]$Arguments) {
    $text = (& $Executable @Arguments | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $Executable $Arguments" }
    return $text
}

function Assert-Equal([string]$Label, [string]$Expected, [string]$Actual) {
    if ($Expected -ne $Actual) {
        throw "$Label differs.`npkgconf: $Expected`nMoonPkgConfig: $Actual"
    }
}

function Invoke-MoonQuery([string]$Directory, [string[]]$Options) {
    return Invoke-Text 'moon' (@('run', '--target', 'native', 'cmd/query', $Directory, $script:Package) + $Options)
}

Push-Location $projectRoot
try {
    if (-not (Test-Path -LiteralPath $Reference)) {
        $command = Get-Command pkgconf -ErrorAction SilentlyContinue
        if ($null -eq $command) { throw "pkgconf reference tool not found: $Reference" }
        $Reference = $command.Source
    }

    $script:Package = 'imagekit'
    $env:PKG_CONFIG_PATH = Join-Path $projectRoot 'examples/valid'
    $env:PKG_CONFIG_LIBDIR = $env:PKG_CONFIG_PATH
    Assert-Equal 'Cflags' (Invoke-Text $Reference @('--cflags', 'imagekit')) (Invoke-MoonQuery 'examples/valid' @('--cflags'))
    Assert-Equal 'dynamic Libs' (Invoke-Text $Reference @('--libs', 'imagekit')) (Invoke-MoonQuery 'examples/valid' @('--libs', '--dedupe-paths'))
    Assert-Equal 'static Libs' (Invoke-Text $Reference @('--static', '--libs', 'imagekit')) (Invoke-MoonQuery 'examples/valid' @('--libs', '--static', '--dedupe-paths'))
    Assert-Equal 'module version' (Invoke-Text $Reference @('--modversion', 'imagekit')) (Invoke-MoonQuery 'examples/valid' @('--modversion'))
    Assert-Equal 'variable' (Invoke-Text $Reference @('--variable=prefix', 'imagekit')) (Invoke-MoonQuery 'examples/valid' @('--variable=prefix'))
    Assert-Equal 'overridden variable' (Invoke-Text $Reference @('--define-variable=prefix=/custom', '--variable=prefix', 'imagekit')) (Invoke-MoonQuery 'examples/valid' @('--variable=prefix', '--define-variable=prefix=/custom'))
    Assert-Equal 'overridden Cflags' (Invoke-Text $Reference @('--define-variable=prefix=/custom', '--cflags', 'imagekit')) (Invoke-MoonQuery 'examples/valid' @('--cflags', '--define-variable=prefix=/custom'))

    $script:Package = 'root'
    $env:PKG_CONFIG_PATH = Join-Path $projectRoot 'examples/order'
    $env:PKG_CONFIG_LIBDIR = $env:PKG_CONFIG_PATH
    Assert-Equal 'diamond Cflags order' (Invoke-Text $Reference @('--cflags', 'root')) (Invoke-MoonQuery 'examples/order' @('--cflags'))
    Assert-Equal 'private dependency order' (Invoke-Text $Reference @('--static', '--libs', 'root')) (Invoke-MoonQuery 'examples/order' @('--libs', '--static'))

    $env:PKG_CONFIG_PATH = Join-Path $projectRoot 'testdata/real-world'
    $env:PKG_CONFIG_LIBDIR = $env:PKG_CONFIG_PATH
    $script:Package = 'zlib'
    Assert-Equal 'zlib template Cflags' (Invoke-Text $Reference @('--cflags', 'zlib')) (Invoke-MoonQuery 'testdata/real-world' @('--cflags'))
    Assert-Equal 'zlib template Libs' (Invoke-Text $Reference @('--libs', 'zlib')) (Invoke-MoonQuery 'testdata/real-world' @('--libs'))
    $script:Package = 'libffi'
    Assert-Equal 'libffi template Cflags' (Invoke-Text $Reference @('--cflags', 'libffi')) (Invoke-MoonQuery 'testdata/real-world' @('--cflags'))
    Assert-Equal 'libffi template Libs' (Invoke-Text $Reference @('--libs', 'libffi')) (Invoke-MoonQuery 'testdata/real-world' @('--libs'))

    $script:Package = 'paths'
    $env:PKG_CONFIG_PATH = Join-Path $projectRoot 'examples/path-policy'
    $env:PKG_CONFIG_LIBDIR = $env:PKG_CONFIG_PATH
    $env:PKG_CONFIG_SYSTEM_INCLUDE_PATH = '/usr/include'
    $env:PKG_CONFIG_SYSTEM_LIBRARY_PATH = '/usr/lib'
    Remove-Item Env:PKG_CONFIG_SYSROOT_DIR -ErrorAction SilentlyContinue
    Assert-Equal 'system Cflags filtering' (Invoke-Text $Reference @('--cflags', 'paths')) (Invoke-MoonQuery 'examples/path-policy' @('--cflags', '--system-include-path=/usr/include'))
    Assert-Equal 'system Libs filtering' (Invoke-Text $Reference @('--libs', 'paths')) (Invoke-MoonQuery 'examples/path-policy' @('--libs', '--system-library-path=/usr/lib'))
    $env:PKG_CONFIG_SYSROOT_DIR = '/sdk'
    Assert-Equal 'sysroot Cflags' (Invoke-Text $Reference @('--cflags', 'paths')) (Invoke-MoonQuery 'examples/path-policy' @('--cflags', '--sysroot=/sdk', '--system-include-path=/usr/include'))
    Assert-Equal 'sysroot Libs' (Invoke-Text $Reference @('--libs', 'paths')) (Invoke-MoonQuery 'examples/path-policy' @('--libs', '--sysroot=/sdk', '--system-library-path=/usr/lib'))
    Remove-Item Env:PKG_CONFIG_SYSROOT_DIR -ErrorAction SilentlyContinue

    $script:Package = 'imagekit'
    $env:PKG_CONFIG_PATH = Join-Path $projectRoot 'examples/valid'
    $env:PKG_CONFIG_LIBDIR = $env:PKG_CONFIG_PATH
    foreach ($option in @('--atleast-version=1.1', '--max-version=1.1', '--exact-version=1.2.0')) {
        & $Reference $option imagekit *> $null
        $referenceStatus = $LASTEXITCODE
        & moon run --target native cmd/query examples/valid imagekit $option *> $null
        $moonStatus = $LASTEXITCODE
        if ($referenceStatus -ne $moonStatus) {
            throw "$option exit status differs: pkgconf=$referenceStatus MoonPkgConfig=$moonStatus"
        }
    }

    $version = Invoke-Text $Reference @('--version')
    Write-Output "pkgconf differential checks: 20 passed (reference $version)"
} finally {
    Pop-Location
    $env:PKG_CONFIG_PATH = $oldPath
    $env:PKG_CONFIG_LIBDIR = $oldLibDir
    $env:PKG_CONFIG_SYSROOT_DIR = $oldSysroot
    $env:PKG_CONFIG_SYSTEM_INCLUDE_PATH = $oldSystemIncludes
    $env:PKG_CONFIG_SYSTEM_LIBRARY_PATH = $oldSystemLibraries
}
