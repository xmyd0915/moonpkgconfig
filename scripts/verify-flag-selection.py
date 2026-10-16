"""Check query modes, JSON origins, shell boundaries and diagnostic exit codes."""

import json
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
MOON = shutil.which("moon")
if MOON is None:
    raise RuntimeError("MoonBit CLI must be installed")


def query(directory, package, *options, status=0):
    result = subprocess.run(
        [MOON, "run", "--target", "native", "cmd/query", str(directory), package, *options],
        cwd=ROOT, text=True, capture_output=True, check=False,
    )
    if result.returncode != status:
        raise AssertionError(
            f"{options}: expected exit {status}, got {result.returncode}\n"
            f"{result.stdout}{result.stderr}"
        )
    return result.stdout.strip()


def check_json(directory, package, options, expected):
    result = json.loads(query(directory, package, *options, "--json"))
    if result["diagnostics"] or [flag["value"] for flag in result["flags"]] != expected:
        raise AssertionError(f"{options}: unexpected result {result}")
    for flag in result["flags"]:
        if flag["package"] != package or flag["location"]["line"] < 1:
            raise AssertionError(f"Origin lost: {flag}")
    return result


group = ["-Wl,--start-group", "-lfirst", "-lsecond", "-Wl,--end-group"]
other_libs = ["-Wl,-rpath,/opt/selection/lib", "-framework", "CoreFoundation", "-pthread", *group]
cases = [
    (["--cflags-only-I"], ["-I/opt/selection/include"]),
    (["--cflags-only-other"], ["-isystem", "/opt/selection/system", "-DMIXED=1", "-pthread"]),
    (["--libs-only-L"], ["-L/opt/selection/lib"]),
    (["--libs-only-l"], ["-lmixed", "-l:exact.a"]),
    (["--libs-only-other"], other_libs),
    (["--libs-only-L", "--static"], ["-L/opt/selection/lib"]),
    (["--libs-only-l", "--static"], ["-lmixed", "-l:exact.a", "-lm"]),
    (["--libs-only-other", "--static"], [*other_libs, "-Wl,--export-dynamic"]),
    (["--cflags-only-I", "--sysroot=/sdk"], ["-I/sdk/opt/selection/include"]),
    (["--libs-only-L", "--system-library-path=/opt/selection/lib"], []),
]
for options, expected in cases:
    result = check_json("examples/flag-selection", "mixed", options, expected)
    if shlex.split(query("examples/flag-selection", "mixed", *options)) != expected:
        raise AssertionError(f"{options}: shell output lost an argument boundary")
    if options == ["--libs-only-l", "--static"]:
        if result["flags"][-1]["field"] != "Libs.private":
            raise AssertionError("Static library lost its private field origin")

check_json("examples/valid", "imagekit", ["--libs-only-other"], [])
explanation = query("examples/valid", "imagekit", "--cflags-only-I", "--explain")
if "via imagekit -> compression" not in explanation or "-DIMAGEKIT=1" in explanation:
    raise AssertionError("Selected explanation has missing origins or unselected flags")

for package, directory in [("broken", "examples/mixed"), ("missing-dependency", "examples/invalid")]:
    failed = json.loads(query(directory, package, "--libs-only-l", "--static", "--json", status=1))
    if "flags" not in failed or not failed["diagnostics"]:
        raise AssertionError("Selection suppressed dependency or parse diagnostics")

for options in [
    ["--cflags-only-I", "--static"],
    ["--libs-only-l", "--libs"],
    ["--cflags-only-I", "--cflags-only-other"],
    ["--modversion", "--json"],
]:
    query("examples/flag-selection", "mixed", *options, status=2)

with tempfile.TemporaryDirectory(prefix="moonpkgconfig-selection-") as directory:
    Path(directory, "quoted.pc").write_text(
        'Name: quoted\nDescription: split and quoted flags\nVersion: 1\n'
        'Cflags: -I "/sdk/include path" -DQUOTED="a b" -isystem "/sdk/system path"\n'
        'Libs: -L "/sdk/lib path" -l quoted\n', encoding="utf-8",
    )
    for option, expected in [
        ("--cflags-only-I", ["-I", "/sdk/include path"]),
        ("--cflags-only-other", ["-DQUOTED=a b", "-isystem", "/sdk/system path"]),
        ("--libs-only-L", ["-L", "/sdk/lib path"]),
        ("--libs-only-l", ["-l", "quoted"]),
    ]:
        check_json(directory, "quoted", [option], expected)
        if shlex.split(query(directory, "quoted", option)) != expected:
            raise AssertionError("Split or quoted operands changed in shell output")

print("Flag selection CLI: JSON, origins, shell boundaries and exit codes passed")
