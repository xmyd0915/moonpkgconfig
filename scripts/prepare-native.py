#!/usr/bin/env python3
"""Prepare pinned static zlib and Expat installations for the native examples."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

from native_ffi import ROOT, msvc_environment


DEPENDENCIES = {
    "zlib": {
        "version": "1.3.1",
        "sha256": "9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23",
        "url": "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz",
        "pc": "share/pkgconfig/zlib.pc",
        "headers": ["zlib.h", "zconf.h"],
    },
    "expat": {
        "version": "2.6.2",
        "sha256": "d4cf38d26e21a56654ffe4acd9cd5481164619626802328506a2869afab29ab3",
        "url": "https://github.com/libexpat/libexpat/releases/download/R_2_6_2/expat-2.6.2.tar.gz",
        "pc": "lib/pkgconfig/expat.pc",
        "headers": ["expat.h", "expat_external.h"],
    },
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def executable(name, purpose):
    found = shutil.which(name)
    if not found:
        raise RuntimeError(f"{purpose} not found: {name}. Install it or supply its executable path.")
    return str(Path(found).resolve())


def version(command, allowed=(0,)):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=60)
    raw = result.stdout + result.stderr
    try:
        output = raw.decode("utf-8").strip()
    except UnicodeDecodeError:
        output = raw.decode("mbcs" if os.name == "nt" else "utf-8", errors="replace").strip()
    if result.returncode not in allowed:
        raise RuntimeError(f"Tool check failed ({result.returncode}): {command[0]}\n{output}")
    return output


def check_tools(args, report):
    if sys.version_info < (3, 9):
        raise RuntimeError("Python 3.9 or newer is required")
    tools = report["tools"]
    tools["python"] = {"path": sys.executable, "version": sys.version.split()[0]}
    moon = executable(args.moon, "MoonBit")
    tools["moon"] = {"path": moon, "version": version([moon, "version", "--all"])}
    cmake = executable(args.cmake, "CMake")
    cmake_version = version([cmake, "--version"])
    tools["cmake"] = {"path": cmake, "version": cmake_version}
    match = re.search(r"cmake version (\d+)\.(\d+)", cmake_version)
    if not match or tuple(map(int, match.groups())) < (3, 15):
        raise RuntimeError("CMake 3.15 or newer is required")
    if os.name == "nt":
        if args.cc:
            raise RuntimeError("--cc is supported on POSIX; Windows uses the discovered x64 MSVC toolchain")
        msvc_environment()
        cc = executable("cl", "MSVC C compiler")
        make = executable("nmake", "MSVC build tool")
        tools["cc"] = {"path": cc, "version": version([cc], allowed=(0, 2))}
        make_version = version([make, "/?"])
        banner = next((line for line in make_version.splitlines()
                       if re.search(r"\d+\.\d+\.\d+", line)), make_version)
        tools["make"] = {"path": make, "version": banner}
    else:
        cc = executable(args.cc or "cc", "C compiler")
        make = executable("make", "Make")
        tools["cc"] = {"path": cc, "version": version([cc, "--version"])}
        tools["make"] = {"path": make, "version": version([make, "--version"])}
    return cmake, cc


def unpack(name, archive, working):
    spec = DEPENDENCIES[name]
    actual = sha256(archive)
    if actual != spec["sha256"]:
        raise RuntimeError(f"{name} {spec['version']} archive SHA-256 mismatch: {actual}")
    expected = f"{name}-{spec['version']}"
    root = working.resolve()
    with tarfile.open(archive, "r:gz") as source:
        for member in source.getmembers():
            path = PurePosixPath(member.name)
            if (path.is_absolute() or ".." in path.parts or "\\" in member.name
                    or ":" in member.name or not path.parts or path.parts[0] != expected
                    or not (member.isfile() or member.isdir())):
                raise RuntimeError(f"Unexpected archive entry: {member.name}")
            target = root.joinpath(*path.parts).resolve()
            if root not in target.parents:
                raise RuntimeError(f"Archive entry escapes workspace: {member.name}")
        source.extractall(working)
    return actual


def download(url, archive):
    started = time.monotonic()
    with urllib.request.urlopen(url, timeout=60) as response, archive.open("wb") as output:
        while True:
            if time.monotonic() - started > 180:
                raise RuntimeError(f"Archive download exceeded 180 seconds: {url}")
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            output.write(chunk)


def build_commands(commands, log, evidence):
    with log.open("w", encoding="utf-8") as output:
        for command in commands:
            evidence["commands"].append(command)
            output.write(json.dumps(command) + "\n")
            output.flush()
            result = subprocess.run(command, cwd=ROOT, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=900)
            if result.returncode:
                raise RuntimeError(f"CMake failed ({result.returncode}); see {log}")


def consumer_prefix(installed, pc_relative, evidence):
    """Quote a separate relocated copy when upstream paths contain spaces."""
    pc = installed / pc_relative
    original_hash = sha256(pc)
    evidence["original_pc_sha256"] = original_hash
    if not any(char.isspace() for char in str(installed)):
        evidence["metadata_quoted_copy"] = False
        return installed
    copied = installed.parent / (installed.name + "-quoted")
    shutil.copytree(installed, copied)
    metadata = pc.read_text(encoding="utf-8").replace(installed.as_posix(), copied.as_posix())
    for variable in ("includedir", "libdir", "sharedlibdir"):
        flag = "-I" if variable == "includedir" else "-L"
        metadata = metadata.replace(flag + "${" + variable + "}", flag + '"${' + variable + '}"')
    (copied / pc_relative).write_text(metadata, encoding="utf-8")
    if sha256(pc) != original_hash:
        raise RuntimeError("Original installation metadata changed while preparing quoted copy")
    evidence["metadata_quoted_copy"] = True
    return copied


def prepare(name, archive_arg, working, cmake, cc, report):
    started = time.monotonic()
    spec = DEPENDENCIES[name]
    evidence = {"version": spec["version"], "archive_url": spec["url"],
                "expected_archive_sha256": spec["sha256"], "commands": []}
    report["dependencies"][name] = evidence
    archive = archive_arg.resolve() if archive_arg else working / f"{name}-{spec['version']}.tar.gz"
    evidence["archive"] = str(archive)
    if not archive_arg:
        print(f"Downloading {name} {spec['version']}", file=sys.stderr, flush=True)
        download(spec["url"], archive)
    evidence["archive_sha256"] = unpack(name, archive, working)
    source = working / f"{name}-{spec['version']}"
    build = working / (name + "-build")
    installed = working / (name + "-installed")
    evidence["original_install_prefix"] = str(installed)
    log = working / (name + "-build.log")
    evidence["build_log"] = str(log)
    generator = "NMake Makefiles" if os.name == "nt" else "Unix Makefiles"
    configure = [cmake, "-S", str(source), "-B", str(build), "-G", generator,
                 "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_INSTALL_PREFIX={installed.as_posix()}",
                 f"-DCMAKE_C_COMPILER={Path(cc).as_posix()}",
                 "-DCMAKE_POSITION_INDEPENDENT_CODE=ON", "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"]
    if name == "zlib":
        # Upstream 1.3.1 always defines shared and static targets. Build only the
        # static target, install its unchanged metadata/headers, and copy its
        # archive ourselves so -lz cannot accidentally select a shared library.
        configure.extend(["-DZLIB_BUILD_EXAMPLES=OFF", "-DSKIP_INSTALL_LIBRARIES=ON"])
        if os.name == "nt":
            configure.extend(["-DCMAKE_POLICY_DEFAULT_CMP0091=NEW",
                              "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"])
        target = "zlibstatic"
        library_name = "zlibstatic.lib" if os.name == "nt" else "libz.a"
    else:
        configure.extend(["-DCMAKE_INSTALL_LIBDIR=lib", "-DEXPAT_SHARED_LIBS=OFF",
                          "-DEXPAT_BUILD_TESTS=OFF", "-DEXPAT_BUILD_EXAMPLES=OFF",
                          "-DEXPAT_BUILD_TOOLS=OFF", "-DEXPAT_BUILD_DOCS=OFF",
                          "-DEXPAT_BUILD_FUZZERS=OFF", "-DEXPAT_BUILD_PKGCONFIG=ON"])
        if os.name == "nt":
            configure.append("-DEXPAT_MSVC_STATIC_CRT=ON")
        target = "expat"
        library_name = "libexpatMT.lib" if os.name == "nt" else "libexpat.a"
    print(f"Building static {name} {spec['version']}; log: {log}", file=sys.stderr, flush=True)
    build_commands([configure, [cmake, "--build", str(build), "--target", target],
                    [cmake, "--install", str(build)]], log, evidence)
    if name == "zlib":
        (installed / "lib").mkdir(exist_ok=True)
        shutil.copy2(build / library_name, installed / "lib" / library_name)
    required = [installed / "lib" / library_name, installed / spec["pc"]]
    required.extend(installed / "include" / header for header in spec["headers"])
    for path in required:
        if not path.is_file():
            raise RuntimeError(f"Expected installed file missing: {path}; see {log}")
    if any(installed.rglob("*.dll")) or any(installed.rglob("*.so*")) or any(installed.rglob("*.dylib")):
        raise RuntimeError(f"Expected an exclusively static {name} installation")
    prefix = consumer_prefix(installed, spec["pc"], evidence)
    library = prefix / "lib" / library_name
    pc = prefix / spec["pc"]
    evidence.update({"install_prefix": str(prefix), "pc_file": str(pc),
                     "pc_sha256": sha256(pc), "static_library": str(library),
                     "library_sha256": sha256(library),
                     "elapsed_seconds": round(time.monotonic() - started, 3)})
    report[name + "_pc_dir"] = str(pc.parent)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon", default="moon", help="installed MoonBit CLI executable")
    parser.add_argument("--cmake", default="cmake", help="installed CMake executable, version 3.15 or newer")
    parser.add_argument("--cc", help="POSIX C compiler executable (default: cc)")
    parser.add_argument("--zlib-archive", type=Path, help="local pinned zlib archive; checksum is still checked")
    parser.add_argument("--expat-archive", type=Path, help="local pinned Expat archive; checksum is still checked")
    parser.add_argument("--report", type=Path, default=ROOT / "_build/verification/native-dependencies.json")
    args = parser.parse_args()
    started = time.monotonic()
    report = {"passed": False, "platform": sys.platform, "tools": {}, "dependencies": {},
              "zlib_pc_dir": None, "expat_pc_dir": None,
              "zlib_msvc_lib": ["z=zlibstatic.lib"] if os.name == "nt" else []}
    destination = args.report.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)

    def save():
        report["elapsed_seconds"] = round(time.monotonic() - started, 3)
        destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Reset a previous success before checking tools, downloading, or building.
    save()
    try:
        cmake, cc = check_tools(args, report)
        temporary = ROOT / ".tmp"
        temporary.mkdir(exist_ok=True)
        working = Path(tempfile.mkdtemp(prefix="native-dependencies-", dir=temporary)).resolve()
        report["workspace"] = str(working)
        for name in DEPENDENCIES:
            prepare(name, getattr(args, name + "_archive"), working, cmake, cc, report)
            save()
        report["passed"] = True
    except (OSError, RuntimeError, ValueError, tarfile.TarError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
    finally:
        save()
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
