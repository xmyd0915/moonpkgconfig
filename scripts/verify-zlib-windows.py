#!/usr/bin/env python3
"""Build pinned zlib with MSVC, then verify MoonBit FFI and quoted Windows paths."""

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

from native_ffi import ROOT, run


VERSION = "1.3.1"
SHA256 = "9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
URL = f"https://github.com/madler/zlib/releases/download/v{VERSION}/zlib-{VERSION}.tar.gz"


def msvc_environment():
    # CMake's NMake generator needs the compiler and SDK environment. Discovery
    # and environment changes remain in this Python process and its children.
    if (shutil.which("cl") and os.environ.get("INCLUDE") and os.environ.get("LIB")
            and os.environ.get("VSCMD_ARG_TGT_ARCH") == "x64"):
        return
    vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / (
        "Microsoft Visual Studio/Installer/vswhere.exe"
    )
    if not vswhere.is_file():
        raise RuntimeError("MSVC not found; install Visual Studio C++ tools and Windows SDK")
    installation = run([
        str(vswhere), "-latest", "-products", "*", "-requires",
        "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath",
    ], ROOT)
    devcmd = Path(installation) / "Common7/Tools/VsDevCmd.bat"
    if not installation or not devcmd.is_file():
        raise RuntimeError("no Visual Studio installation with x64 C++ tools was found")
    if any(character in str(devcmd) for character in ('"', '%', '\n', '\r')):
        raise RuntimeError("unsupported Visual Studio installation path")
    # Only this trusted installation script runs through cmd. Metadata flags
    # never pass through it. Do not print the captured environment.
    result = subprocess.run(
        f'"{os.environ.get("COMSPEC", "cmd.exe")}" /d /u /s /c '
        f'""{devcmd}" -no_logo -arch=x64 -host_arch=x64 >nul && set"',
        cwd=ROOT, text=True, encoding="utf-16-le", errors="replace", capture_output=True,
    )
    if result.returncode:
        raise RuntimeError("initializing the Visual Studio x64 environment failed")
    for line in result.stdout.splitlines():
        name, separator, value = line.partition("=")
        if separator and name and not name.startswith("="):
            os.environ[name] = value
    if not shutil.which("cl") or not shutil.which("nmake"):
        raise RuntimeError("Visual Studio did not provide cl and nmake")


def unpack(archive, destination):
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise RuntimeError(f"zlib {VERSION} archive SHA-256 mismatch")
    with tarfile.open(archive, "r:gz") as source:
        for member in source.getmembers():
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or "\\" in member.name or (
                not path.parts or path.parts[0] != f"zlib-{VERSION}"
            ) or not (member.isfile() or member.isdir()):
                raise RuntimeError(f"unexpected archive entry: {member.name}")
        source.extractall(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--cmake", default="cmake", help="CMake executable (3.15 or newer)")
    parser.add_argument("--archive", type=Path, help="optional local pinned zlib archive; checksum is still checked")
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("this verification requires Windows x64 and MSVC")
    cmake = shutil.which(args.cmake)
    moon = shutil.which(args.moon)
    if not cmake or not moon:
        parser.error("CMake and MoonBit must be installed; --cmake/--moon may specify executables")
    msvc_environment()
    temporary_root = ROOT / ".tmp"
    temporary_root.mkdir(exist_ok=True)
    # Keep the actual installation and log for inspection; no tracked files change.
    working = Path(tempfile.mkdtemp(prefix="windows-zlib-", dir=temporary_root))
    print(f"Windows zlib workspace: {working}", flush=True)
    archive = args.archive.resolve() if args.archive else working / f"zlib-{VERSION}.tar.gz"
    if not args.archive:
        with urllib.request.urlopen(URL, timeout=60) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
    unpack(archive, working)
    source = working / f"zlib-{VERSION}"
    build = working / "build"
    installed = working / "installed"
    commands = [
        [cmake, "-S", str(source), "-B", str(build), "-G", "NMake Makefiles",
         "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_INSTALL_PREFIX={installed.as_posix()}",
         "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW", "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded",
         "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", "-DZLIB_BUILD_EXAMPLES=OFF"],
        [cmake, "--build", str(build)],
        [cmake, "--install", str(build)],
    ]
    log = working / "build.log"
    with log.open("w", encoding="utf-8") as output:
        for command in commands:
            result = subprocess.run(command, cwd=ROOT, text=True, stdout=output, stderr=subprocess.STDOUT)
            if result.returncode:
                raise RuntimeError(f"CMake failed ({result.returncode}); see {log}")
    if not (installed / "lib/zlibstatic.lib").is_file():
        raise RuntimeError("MSVC build did not install zlibstatic.lib")
    script = ROOT / "scripts/verify-zlib-ffi.py"

    def verify(prefix):
        command = [sys.executable, str(script), "--moon", moon, "--pc-dir",
                   str(prefix / "share/pkgconfig"), "--msvc-lib", "z=zlibstatic.lib"]
        print(run(command, ROOT), flush=True)

    print("Verify unchanged upstream installation metadata", flush=True)
    verify(installed)
    spaced = working / "zlib with spaces"
    shutil.copytree(installed, spaced)
    pc = spaced / "share/pkgconfig/zlib.pc"
    metadata = pc.read_text(encoding="utf-8").replace(installed.as_posix(), spaced.as_posix())
    # Upstream 1.3.1 omits quoting. The separate relocated fixture supplies valid
    # .pc quoting; the original installed metadata above remains untouched.
    metadata = metadata.replace("-I${includedir}", '-I"${includedir}"')
    metadata = metadata.replace("-L${libdir}", '-L"${libdir}"')
    metadata = metadata.replace("-L${sharedlibdir}", '-L"${sharedlibdir}"')
    pc.write_text(metadata, encoding="utf-8")
    print("Verify copied installation with explicitly quoted space paths", flush=True)
    verify(spaced)
    print("Windows MSVC zlib integration: 2 installations passed", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, tarfile.TarError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
