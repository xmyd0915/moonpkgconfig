#!/usr/bin/env python3
"""Build a file compressor using the published MoonPkgConfig API and installed zlib."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import zlib


ROOT = Path(__file__).resolve().parent
MODULE = "xmyd0915/moonpkgconfig"
VERSION = "0.2.0"


def run(command, directory, status=0):
    result = subprocess.run(command, cwd=directory, text=True, encoding="utf-8",
                            errors="replace", capture_output=True)
    if result.returncode != status:
        raise RuntimeError(f"Expected exit {status}, got {result.returncode}: "
                           f"{shlex.join(command)}\n{result.stdout}{result.stderr}")
    return result.stdout.strip()


def msvc_arguments(flags, compile_mode, mappings):
    prefixes = {"-I": "/I", "-D": "/D", "-U": "/U"} if compile_mode else {
        "-L": "/LIBPATH:", "-l": "",
    }
    output = []
    index = 0
    while index < len(flags):
        flag = flags[index]
        value = flag["value"]
        prefix = value[:2]
        if prefix not in prefixes:
            raise RuntimeError(f"Unsupported MSVC option {value!r} from {flag['package']}:{flag['field']}")
        operand = value[2:]
        if not operand:
            index += 1
            if index >= len(flags) or any(flags[index][key] != flag[key] for key in (
                "package", "field", "location",
            )) or not flags[index]["value"] or flags[index]["value"].startswith("-"):
                raise RuntimeError(f"Missing operand for {prefix}")
            operand = flags[index]["value"]
        if prefix == "-l":
            if not re.fullmatch(r"[A-Za-z0-9_+][A-Za-z0-9_+.-]*", operand):
                raise RuntimeError(f"Unsupported MSVC library {operand!r}")
            output.append(mappings.get(operand, operand + ".lib"))
        else:
            output.append(prefixes[prefix] + operand)
        index += 1
    return ["/utf-8", "/MT", *output] if compile_mode else ["/link", *output]


def diagnostics(plan):
    unique = []
    for section in ("cflags", "libs"):
        for problem in plan[section]["diagnostics"]:
            if problem not in unique:
                unique.append(problem)
    return unique


def show_problem(problem):
    location = problem["location"]
    print(f"{problem['code']} {location['source']}:{location['line']}:{location['column']} "
          f"{problem['message']}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pc-dir", type=Path, required=True)
    parser.add_argument("--path", type=Path, action="append", default=[])
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--cc", help="POSIX C compiler; Windows defaults to MoonBit's MSVC discovery")
    parser.add_argument("--msvc-lib", action="append", default=[], metavar="NAME=FILE.lib")
    parser.add_argument("--demo", action="store_true", help="also replay dependency failures and verify file interoperability")
    args = parser.parse_args()
    moon = shutil.which(args.moon)
    compiler_name = args.cc or (None if os.name == "nt" else "cc")
    compiler = shutil.which(compiler_name) if compiler_name else None
    if not moon or (compiler_name and not compiler):
        parser.error("MoonBit and the selected compiler must be installed")
    if os.name == "nt" and compiler and Path(compiler).stem.lower() not in ("cl", "clang-cl"):
        parser.error("Windows requires an MSVC-compatible compiler")
    directories = [path.resolve() for path in (args.pc_dir, *args.path)]
    if not all(path.is_dir() for path in directories) or not (directories[0] / "zlib.pc").is_file():
        parser.error("--pc-dir must contain installed zlib.pc; every search directory must exist")
    mappings = {}
    for mapping in args.msvc_lib:
        name, separator, filename = mapping.partition("=")
        if os.name != "nt" or not separator or not re.fullmatch(r"[A-Za-z0-9_+][A-Za-z0-9_+.-]*", name) or not re.fullmatch(r"[A-Za-z0-9_+][A-Za-z0-9_+.-]*\.lib", filename) or name in mappings:
            parser.error("--msvc-lib requires a unique NAME=FILE.lib mapping on Windows")
        mappings[name] = filename
    for parent in (ROOT, *ROOT.parents):
        if (parent / "moon.work").exists():
            raise RuntimeError("Run this consumer outside moon.work overrides")
    run([moon, "update"], ROOT)
    run([moon, "run", "--target", "native", "--deny-warn", "--build-only", "cmd/plan"], ROOT)
    installed = ROOT / ".mooncakes" / MODULE / "moon.mod"
    if not installed.is_file() or not re.search(r'^version\s*=\s*"0\.2\.0"', installed.read_text(encoding="utf-8"), re.MULTILINE):
        raise RuntimeError("The consumer must use MoonCakes MoonPkgConfig 0.2.0")
    print(f"Dependency: {MODULE}@{VERSION} (MoonCakes)", flush=True)
    build_root = ROOT / "_build"
    working = Path(tempfile.mkdtemp(prefix="consumer-", dir=build_root))
    source_pc = (ROOT / "compression-app.pc").read_text(encoding="utf-8")
    evidence = {"dependency": MODULE + "@" + VERSION, "scenarios": []}

    def query(case, metadata, paths, status):
        directory = working / case
        directory.mkdir()
        (directory / "compression-app.pc").write_text(metadata, encoding="utf-8")
        command = [moon, "run", "--target", "native", "--deny-warn", "cmd/plan",
                   str(directory), *map(str, paths)]
        plan = json.loads(run(command, ROOT, status))
        evidence["scenarios"].append({"case": case, "exit": status, "plan": plan})
        return plan

    if args.demo:
        for case, metadata, paths, code in (
            ("missing", source_pc, [], "PC015"),
            ("version", source_pc.replace("zlib >= 1.2.13", "zlib >= 999.0"), directories, "PC016"),
        ):
            print(f"\nDependency failure: {case}", flush=True)
            plan = query(case, metadata, paths, 1)
            problems = diagnostics(plan)
            if len(problems) != 1 or problems[0]["code"] != code or problems[0]["location"]["line"] != 4:
                raise RuntimeError(f"Unexpected {case} diagnostics: {problems}")
            show_problem(problems[0])
    print("\nRepaired dependency plan", flush=True)
    plan = query("ready", source_pc, directories, 0)
    if diagnostics(plan) or plan["dependency_path"] != ["compression-app", "zlib"]:
        raise RuntimeError("Expected a clean private dependency path to zlib")
    print(f"zlib {plan['zlib_version']}; via " + " -> ".join(plan["dependency_path"]), flush=True)
    native = {}
    for section in ("cflags", "libs"):
        for flag in plan[section]["flags"]:
            location = flag["location"]
            print(f"  {flag['value']} <- {flag['package']}:{flag['field']} "
                  f"[{location['source']}:{location['line']}]", flush=True)
    compile_flags = plan["cflags"]["flags"]
    link_flags = plan["libs"]["flags"]
    if os.name == "nt":
        compile_values = msvc_arguments(compile_flags, True, mappings)
        link_values = msvc_arguments(link_flags, False, mappings)
    else:
        compile_values = [flag["value"] for flag in compile_flags]
        link_values = [flag["value"] for flag in link_flags]
    native.update({"cc-flags": shlex.join(compile_values), "stub-cc-flags": shlex.join(compile_values),
                   "cc-link-flags": shlex.join(link_values)})
    if compiler:
        native.update({"cc": compiler, "stub-cc": compiler})
    application = working / "application"
    shutil.copytree(ROOT / "app", application, ignore=shutil.ignore_patterns("_build", ".mooncakes"))
    package = application / "moon.pkg"
    manifest = package.read_text(encoding="utf-8")
    marker = '"native-stub": [ "zlib_stub.c" ],'
    if manifest.count(marker) != 1:
        raise RuntimeError("Unexpected compressor package template")
    package.write_text(manifest.replace(marker, marker + "\n  link: " +
                       json.dumps({"native": native}, indent=2) + ","), encoding="utf-8")
    run([moon, "run", "--target", "native", "--deny-warn", "--build-only", "."], application)
    binary = application / "_build/native/debug/build" / ("compressor.exe" if os.name == "nt" else "compressor")
    if not binary.is_file():
        raise RuntimeError(f"Compressor executable not found: {binary}")
    if args.demo:
        checks = []
        for label, content in (("empty", b""), ("text", b"MoonPkgConfig builds a real file compressor.\n" * 100),
                               ("binary", bytes(range(256)) * 2048)):
            original = working / (label + ".input")
            compressed = working / (label + ".zlib")
            restored = working / (label + ".restored")
            foreign = working / (label + ".python-zlib")
            foreign_restored = working / (label + ".python-restored")
            original.write_bytes(content)
            print(run([str(binary), "compress", str(original), str(compressed)], working), flush=True)
            print(run([str(binary), "decompress", str(compressed), str(restored)], working), flush=True)
            if restored.read_bytes() != content or zlib.decompress(compressed.read_bytes()) != content:
                raise RuntimeError(f"File round trip or Python zlib oracle differs: {label}")
            foreign.write_bytes(zlib.compress(content))
            run([str(binary), "decompress", str(foreign), str(foreign_restored)], working)
            if foreign_restored.read_bytes() != content:
                raise RuntimeError(f"Reading Python zlib output differs: {label}")
            checks.append({"input": label, "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()})
        corrupt = working / "corrupt.zlib"
        rejected = working / "corrupt.output"
        corrupt.write_bytes(b"not a zlib stream")
        run([str(binary), "decompress", str(corrupt), str(rejected)], working, 1)
        if rejected.exists():
            raise RuntimeError("Corrupt input created an output file")
        preserved = working / "existing.output"
        preserved.write_bytes(b"keep this file")
        run([str(binary), "compress", str(original), str(preserved)], working, 1)
        if preserved.read_bytes() != b"keep this file":
            raise RuntimeError("Existing output was overwritten")
        evidence["files"] = checks
        evidence["corrupt_input_rejected"] = True
        evidence["existing_output_preserved"] = True
        print("\nPublished consumer: 2 dependency failures, repaired build and 3 interoperable file round trips passed", flush=True)
    (working / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(f"Executable: {binary}\nEvidence: {working / 'evidence.json'}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error))
