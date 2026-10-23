"""Prepare native libraries, diagnose dependency errors and build published-package applications."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from native_ffi import ROOT


def run_script(name, arguments):
    command = [sys.executable, str(ROOT / "scripts" / name), *arguments]
    result = subprocess.run(command, cwd=ROOT)
    if result.returncode:
        raise RuntimeError(f"{name} failed with exit {result.returncode}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zlib-pc-dir", type=Path, help="reuse installed zlib; supply both library directories")
    parser.add_argument("--expat-pc-dir", type=Path, help="reuse installed static Expat")
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--cmake", default="cmake")
    parser.add_argument("--cc")
    parser.add_argument("--zlib-archive", type=Path, help="local pinned archive for preparation")
    parser.add_argument("--expat-archive", type=Path, help="local pinned archive for preparation")
    parser.add_argument("--zlib-msvc-lib", action="append", default=[])
    args = parser.parse_args()
    if bool(args.zlib_pc_dir) != bool(args.expat_pc_dir):
        parser.error("Supply both --zlib-pc-dir and --expat-pc-dir, or neither to prepare fixed versions")
    if args.zlib_pc_dir and (args.zlib_archive or args.expat_archive):
        parser.error("Archive options apply only when preparing libraries")
    temporary = ROOT / ".tmp"
    temporary.mkdir(exist_ok=True)
    working = Path(tempfile.mkdtemp(prefix="native-walkthrough-", dir=temporary))
    report = ROOT / "_build/verification/native-walkthrough.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    evidence = {"dependency": "xmyd0915/moonpkgconfig@0.3.1", "passed": False,
                "workspace": str(working), "consumers": []}
    # Clear a previous success before running any preparation or consumer process.
    report.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    try:
        mappings = list(args.zlib_msvc_lib)
        if args.zlib_pc_dir:
            zlib_directory, expat_directory = args.zlib_pc_dir.resolve(), args.expat_pc_dir.resolve()
            for directory, filename in ((zlib_directory, "zlib.pc"), (expat_directory, "expat.pc")):
                if not (directory / filename).is_file():
                    raise RuntimeError(f"Installed metadata not found: {directory / filename}")
        else:
            print("Prepare fixed zlib and Expat installations", flush=True)
            prepared_report = working / "dependencies.json"
            options = ["--moon", args.moon, "--cmake", args.cmake, "--report", str(prepared_report)]
            if args.cc:
                options.extend(["--cc", args.cc])
            for name, archive in (("--zlib-archive", args.zlib_archive), ("--expat-archive", args.expat_archive)):
                if archive:
                    options.extend([name, str(archive.resolve())])
            try:
                run_script("prepare-native.py", options)
            finally:
                if prepared_report.is_file():
                    evidence["preparation"] = json.loads(prepared_report.read_text(encoding="utf-8"))
            prepared = evidence["preparation"]
            if not prepared["passed"]:
                raise RuntimeError("Native dependency preparation did not complete")
            zlib_directory, expat_directory = Path(prepared["zlib_pc_dir"]), Path(prepared["expat_pc_dir"])
            if not mappings:
                mappings = prepared["zlib_msvc_lib"]
            evidence["preparation"] = prepared
        evidence["search_directories"] = {"zlib": str(zlib_directory), "expat": str(expat_directory)}
        reports = []
        for library, directory in (("zlib", zlib_directory), ("expat", expat_directory)):
            print(f"\nBuild {library}: missing, incompatible and damaged dependencies, repair, execution", flush=True)
            options = ["--library", library, "--pc-dir", str(directory), "--moon", args.moon]
            if args.cc:
                options.extend(["--cc", args.cc])
            if library == "zlib":
                for mapping in mappings:
                    options.extend(["--msvc-lib", mapping])
            run_script("verify-native-consumer.py", options)
            name = "native-consumer-" + library + ".json"
            result = json.loads((report.parent / name).read_text(encoding="utf-8"))
            if not result["passed"]:
                raise RuntimeError(f"{library} consumer did not pass")
            reports.append(result)
            evidence["consumers"].append(name)
        print("\nBuild a file tool with the same planner and adapter", flush=True)
        options = ["--pc-dir", str(zlib_directory), "--moon", args.moon]
        if args.cc:
            options.extend(["--cc", args.cc])
        for mapping in mappings:
            options.extend(["--msvc-lib", mapping])
        run_script("verify-native-file-tool.py", options)
        file_result = json.loads((report.parent / "native-file-tool.json").read_text(encoding="utf-8"))
        if not file_result["passed"]:
            raise RuntimeError("File tool verification did not pass")
        reports.append(file_result)
        evidence["consumers"].append("native-file-tool.json")
        if any(item["template_sha256"] != reports[0]["template_sha256"] for item in reports[1:]):
            raise RuntimeError("Applications did not use identical planner and adapter source")
        evidence["executable"] = file_result["executable"]
        evidence["passed"] = True
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        evidence["error"] = str(error)
        raise
    finally:
        evidence["elapsed_seconds"] = round(time.monotonic() - started, 3)
        report.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\nNative walkthrough: passed in {evidence['elapsed_seconds']:.1f}s; {report}", flush=True)
    print(f"Executable: {evidence['executable']}", flush=True)
    print("Use the executable with: compress <input> <output.zlib> or decompress <input.zlib> <output>", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error))
