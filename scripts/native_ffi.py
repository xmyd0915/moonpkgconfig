"""Common build glue for the independent native FFI examples."""

import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def run(command, directory, expected_status=0):
    result = subprocess.run(
        command, cwd=directory, text=True, capture_output=True, check=False
    )
    if result.returncode != expected_status:
        raise RuntimeError(
            f"Command returned {result.returncode}, expected {expected_status}: "
            f"{shlex.join(command)}\n{result.stdout}{result.stderr}"
        )
    return result.stdout.strip()


def arguments(description):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument(
        "--pc-dir", type=Path, required=True,
        help="directory containing the root library's installed .pc file",
    )
    parser.add_argument(
        "--path", type=Path, action="append", default=[],
        help="additional dependency search directory; may be repeated",
    )
    parser.add_argument("--moon", default="moon", help="MoonBit CLI executable")
    parser.add_argument("--cc", default="cc", help="POSIX C compiler executable")
    args = parser.parse_args()
    if os.name == "nt":
        parser.error("these examples require a POSIX native toolchain (Linux or macOS)")
    moon = shutil.which(args.moon)
    compiler = shutil.which(args.cc)
    if moon is None or compiler is None:
        parser.error("MoonBit and the selected C compiler must be installed")
    directories = [path.resolve() for path in [args.pc_dir, *args.path]]
    if not all(path.is_dir() for path in directories):
        parser.error("every explicit pkg-config search directory must exist")
    return moon, compiler, directories


def query_command(moon, directories, package, mode, static=False):
    command = [
        moon, "run", "--target", "native", "cmd/query",
        str(directories[0]), package, mode,
    ]
    for directory in directories[1:]:
        command.extend(["--path", str(directory)])
    if mode in ("--cflags", "--libs"):
        command.append("--json")
    if static:
        command.append("--static")
    return command


def query(moon, directories, package, mode, static=False):
    output = run(query_command(moon, directories, package, mode, static), ROOT)
    if mode not in ("--cflags", "--libs"):
        return output
    result = json.loads(output)
    if result["diagnostics"]:
        raise RuntimeError(f"{package} metadata has diagnostics: {result['diagnostics']}")
    return result["flags"]


def values(flags):
    return [flag["value"] for flag in flags]


def temporary_directory(prefix):
    temporary_root = ROOT / ".tmp"
    temporary_root.mkdir(exist_ok=True)
    return tempfile.TemporaryDirectory(prefix=prefix, dir=temporary_root)


def build_example(moon, compiler, example, stub, cflags, libs, success):
    with temporary_directory(example + "-") as name:
        consumer = Path(name)
        for filename in ("moon.mod", "main.mbt", stub):
            shutil.copyfile(ROOT / "examples" / example / filename, consumer / filename)
        # Native manifests store flag fragments as strings. Quote individual
        # JSON array elements; no metadata is evaluated by a shell.
        native = {
            "cc": compiler,
            "stub-cc": compiler,
            "cc-flags": shlex.join(values(cflags)),
            "stub-cc-flags": shlex.join(values(cflags)),
            "cc-link-flags": shlex.join(values(libs)),
        }
        manifest = (
            'pkgtype(kind: "executable")\n\noptions(\n'
            f'  "native-stub": [ {json.dumps(stub)} ],\n'
            f'  link: {json.dumps({"native": native}, indent=2)},\n)\n'
        )
        (consumer / "moon.pkg").write_text(manifest, encoding="utf-8")
        output = run([moon, "run", "--target", "native", "--deny-warn", "."], consumer)
        if output != success:
            raise RuntimeError(f"Unexpected FFI program output:\n{output}")
        print(output)
