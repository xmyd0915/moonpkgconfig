"""Build pinned static Expat with CMake, then run the actual MoonBit consumer."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

from native_ffi import ROOT, msvc_environment, run


VERSION = "2.6.2"
SHA256 = "d4cf38d26e21a56654ffe4acd9cd5481164619626802328506a2869afab29ab3"
URL = f"https://github.com/libexpat/libexpat/releases/download/R_2_6_2/expat-{VERSION}.tar.gz"


def unpack(archive, destination):
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise RuntimeError("Expat archive SHA-256 mismatch")
    with tarfile.open(archive, "r:gz") as source:
        for member in source.getmembers():
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or "\\" in member.name or (
                not path.parts or path.parts[0] != f"expat-{VERSION}"
            ) or not (member.isfile() or member.isdir()):
                raise RuntimeError("Unexpected archive entry: " + member.name)
        source.extractall(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cmake", default="cmake")
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--archive", type=Path, help="local pinned archive; checksum is still checked")
    parser.add_argument("--with-native-consumer", action="store_true", help="also verify the generic MoonCakes 0.3.1 template")
    args = parser.parse_args()
    cmake, moon = shutil.which(args.cmake), shutil.which(args.moon)
    if not cmake or not moon:
        parser.error("CMake and MoonBit must be installed")
    if os.name == "nt":
        msvc_environment()
    temporary = ROOT / ".tmp"
    temporary.mkdir(exist_ok=True)
    working = Path(tempfile.mkdtemp(prefix="expat-", dir=temporary))
    print("Expat workspace: " + str(working), flush=True)
    archive = args.archive.resolve() if args.archive else working / f"expat-{VERSION}.tar.gz"
    if not args.archive:
        with urllib.request.urlopen(URL, timeout=60) as response, archive.open("wb") as destination:
            shutil.copyfileobj(response, destination)
    unpack(archive, working)
    source, build, installed = working / f"expat-{VERSION}", working / "build", working / "installed"
    generator = "NMake Makefiles" if os.name == "nt" else "Unix Makefiles"
    configure = [cmake, "-S", str(source), "-B", str(build), "-G", generator,
                 "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_INSTALL_PREFIX={installed.as_posix()}",
                 "-DCMAKE_INSTALL_LIBDIR=lib", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
                 "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", "-DEXPAT_SHARED_LIBS=OFF",
                 "-DEXPAT_BUILD_TESTS=OFF", "-DEXPAT_BUILD_EXAMPLES=OFF", "-DEXPAT_BUILD_TOOLS=OFF",
                 "-DEXPAT_BUILD_DOCS=OFF", "-DEXPAT_BUILD_FUZZERS=OFF", "-DEXPAT_BUILD_PKGCONFIG=ON"]
    if os.name == "nt":
        configure.append("-DEXPAT_MSVC_STATIC_CRT=ON")
    log = working / "build.log"
    with log.open("w", encoding="utf-8") as output:
        for command in [configure, [cmake, "--build", str(build)], [cmake, "--install", str(build)]]:
            result = subprocess.run(command, cwd=ROOT, text=True, stdout=output, stderr=subprocess.STDOUT)
            if result.returncode:
                raise RuntimeError(f"CMake failed ({result.returncode}); see {log}")
    library = installed / "lib" / ("libexpatMT.lib" if os.name == "nt" else "libexpat.a")
    if not library.is_file() or any(installed.rglob("*.dll")) or any(installed.rglob("*.so*")):
        raise RuntimeError("Expected an exclusively static Expat installation")
    pc = installed / "lib/pkgconfig/expat.pc"
    before = hashlib.sha256(pc.read_bytes()).hexdigest()
    command = [sys.executable, str(ROOT / "scripts/verify-expat-ffi.py"),
               "--moon", moon, "--pc-dir", str(pc.parent)]
    print(run(command, ROOT), flush=True)
    if hashlib.sha256(pc.read_bytes()).hexdigest() != before:
        raise RuntimeError("Installed expat.pc changed during verification")
    destination = ROOT / "_build/verification/expat.json"
    evidence = json.loads(destination.read_text(encoding="utf-8"))
    evidence.update({"archive_url": URL, "archive_sha256": SHA256, "build_log": str(log),
                     "static_library": str(library), "library_sha256": hashlib.sha256(library.read_bytes()).hexdigest()})
    destination.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Static Expat build and MoonBit integration: passed", flush=True)
    if args.with_native_consumer:
        command = [sys.executable, str(ROOT / "scripts/verify-native-consumer.py"),
                   "--library", "expat", "--moon", moon, "--pc-dir", str(pc.parent)]
        print(run(command, ROOT), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, tarfile.TarError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
