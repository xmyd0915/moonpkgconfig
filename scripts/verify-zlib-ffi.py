#!/usr/bin/env python3
"""Build a native MoonBit consumer using flags queried from an installed zlib.pc."""

import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
SUCCESS = "MoonBit zlib FFI: CRC-32, 3 round trips and 3 error cases passed"


def run(command, directory):
    result = subprocess.run(
        command, cwd=directory, text=True, capture_output=True, check=False
    )
    if result.returncode:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {shlex.join(command)}\n"
            f"{result.stdout}{result.stderr}"
        )
    return result.stdout.strip()


def query(moon, pc_dir, mode):
    command = [
        moon, "run", "--target", "native", "cmd/query", str(pc_dir), "zlib", mode
    ]
    if mode in ("--cflags", "--libs"):
        command.append("--json")
        if mode == "--libs":
            command.append("--static")
        result = json.loads(run(command, ROOT))
        if result["diagnostics"]:
            raise RuntimeError(f"zlib metadata has diagnostics: {result['diagnostics']}")
        return [flag["value"] for flag in result["flags"]]
    return run(command, ROOT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pc-dir", type=Path, required=True,
        help="directory containing installed zlib.pc",
    )
    parser.add_argument("--moon", default="moon", help="MoonBit CLI executable")
    parser.add_argument("--cc", default="cc", help="POSIX C compiler executable")
    args = parser.parse_args()
    if os.name == "nt":
        parser.error("this example requires a POSIX native toolchain (Linux or macOS)")
    moon = shutil.which(args.moon)
    compiler = shutil.which(args.cc)
    if moon is None or compiler is None:
        parser.error("MoonBit and the selected C compiler must be installed")
    pc_dir = args.pc_dir.resolve()
    if not (pc_dir / "zlib.pc").is_file():
        parser.error(f"no installed zlib.pc in {pc_dir}")

    version = query(moon, pc_dir, "--modversion")
    cflags = query(moon, pc_dir, "--cflags")
    libs = query(moon, pc_dir, "--libs")
    print(f"Installed zlib: {version}")
    print(f"Cflags from MoonPkgConfig: {json.dumps(cflags)}")
    print(f"Static Libs from MoonPkgConfig: {json.dumps(libs)}")

    temporary_root = ROOT / ".tmp"
    temporary_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="zlib-ffi-", dir=temporary_root) as name:
        consumer = Path(name)
        for filename in ("moon.mod", "main.mbt", "zlib_stub.c"):
            shutil.copyfile(
                ROOT / "examples" / "zlib-ffi" / filename, consumer / filename
            )
        # Moon's native manifest stores flag fragments as strings. Quote each
        # element from the JSON array; never evaluate .pc output in a shell.
        native = {
            "cc": compiler,
            "stub-cc": compiler,
            "cc-flags": shlex.join(cflags),
            "stub-cc-flags": shlex.join(cflags),
            "cc-link-flags": shlex.join(libs),
        }
        manifest = (
            'pkgtype(kind: "executable")\n\noptions(\n'
            '  "native-stub": [ "zlib_stub.c" ],\n'
            f'  link: {json.dumps({"native": native}, indent=2)},\n)\n'
        )
        (consumer / "moon.pkg").write_text(manifest, encoding="utf-8")
        output = run([moon, "run", "--target", "native", "--deny-warn"], consumer)
        if output != SUCCESS:
            raise RuntimeError(f"Unexpected FFI program output:\n{output}")
        print(output)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
