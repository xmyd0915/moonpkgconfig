"""Verify native CLI resource bounds in fresh processes on Linux and Windows."""

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
MIB = 1024 * 1024
MAX_RSS_BYTES = 500 * MIB
MAX_OUTPUT_BYTES = MIB


def peak_reader(process):
    if os.name == "nt":
        from ctypes import wintypes

        class Counters(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                        *[(name, ctypes.c_size_t) for name in (
                            "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
                            "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage",
                            "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage")]]

        get_info = ctypes.WinDLL("psapi", use_last_error=True).GetProcessMemoryInfo
        get_info.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
        get_info.restype = wintypes.BOOL
        counters = Counters()
        counters.cb = ctypes.sizeof(counters)

        def read():
            if get_info(wintypes.HANDLE(int(process._handle)), ctypes.byref(counters), counters.cb):
                return counters.PeakWorkingSetSize
            return None

        return read

    def read():
        try:
            status = Path(f"/proc/{process.pid}/status").read_text(encoding="ascii")
        except (FileNotFoundError, ProcessLookupError):
            return None
        match = re.search(r"^VmHWM:\s+(\d+)\s+kB$", status, re.MULTILINE)
        return int(match.group(1)) * 1024 if match else None

    return read


def measure(spec):
    """This worker launches exactly one child; Linux rusage is therefore per case."""
    peak = 0
    stopped = None
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        start = time.perf_counter()
        process = subprocess.Popen(spec["command"], cwd=spec["cwd"], stdout=stdout, stderr=stderr)
        sample = peak_reader(process)
        try:
            while True:
                peak = max(peak, sample() or 0)
                if process.poll() is not None:
                    break
                if time.perf_counter() - start > spec["timeout_seconds"]:
                    stopped = "timeout"
                elif peak >= MAX_RSS_BYTES:
                    stopped = "memory limit"
                elif os.fstat(stdout.fileno()).st_size + os.fstat(stderr.fileno()).st_size > MAX_OUTPUT_BYTES:
                    stopped = "output limit"
                if stopped:
                    process.kill()
                    break
                time.sleep(0.01)
            process.wait(timeout=5)
            elapsed = time.perf_counter() - start
            peak = max(peak, sample() or 0)
            if sys.platform == "linux":
                import resource
                # A new Python worker has no earlier children. Linux reports KiB.
                peak = max(peak, resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss * 1024)
            sizes = [os.fstat(stream.fileno()).st_size for stream in (stdout, stderr)]
            stdout.seek(0)
            stderr.seek(0)
            return {"exit": process.returncode, "wall_seconds": round(elapsed, 6),
                    "peak_rss_bytes": peak or None, "stopped": stopped,
                    "stdout_bytes": sizes[0], "stderr_bytes": sizes[1],
                    "stdout": stdout.read(MAX_OUTPUT_BYTES + 1).decode("utf-8", errors="replace" if stopped else "strict"),
                    "stderr": stderr.read(MAX_OUTPUT_BYTES + 1).decode("utf-8", errors="replace" if stopped else "strict")}
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)


def build_cli(moon, target):
    executable = shutil.which(moon)
    if executable is None:
        raise RuntimeError("MoonBit CLI must be installed, or pass --cli")
    result = subprocess.run([executable, "build", "--target", "native", "--release",
                             "--target-dir", str(target), "cmd/moonpkgconfig"],
                            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=180)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    directory = target / "native/release/build/cmd/moonpkgconfig"
    candidates = [directory / name for name in ("moonpkgconfig", "moonpkgconfig.exe")
                  if (directory / name).is_file()]
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one executable in {directory}, found {candidates}")
    return candidates[0]


def fixtures(workspace):
    def write(path, text):
        # Keep exact fixture bytes across platforms, including LF line endings.
        path.write_bytes(text.encode("utf-8"))

    header = "Name: bomb\nDescription: d\nVersion: 1\na=" + "x" * 1000 + "\nb=" + "${a}" * 1000 + "\n"
    directories = {name: workspace / name for name in ("repeated-expansion", "many-diagnostics", "many-documents")}
    for directory in directories.values():
        directory.mkdir()
        write(directory / "zz_good.pc",
              "Name: good\nDescription: valid later entry\nVersion: 1\nCflags: -DGOOD=1\nLibs: -lgood\n")
    write(directories["repeated-expansion"] / "cpu.pc",
          header + "".join(f"c{i}=${{b}}${{b}}\n" for i in range(100000)))
    write(directories["many-diagnostics"] / "bad.pc",
          "Name: bad\nDescription: d\nVersion: 1\n" + "".join(f"x{i}\n" for i in range(40000)))
    write(directories["many-diagnostics"] / "root.pc",
          "Name: root\nDescription: bad dependency\nVersion: 1\nRequires: bad\nLibs: -lroot\n")
    payload = header + "".join(f"c{i}=${{b}}\n" for i in range(15))
    for index in range(150):
        write(directories["many-documents"] / f"f{index:03}.pc", payload)
    return directories


def verify(case, result):
    if result["stopped"]:
        raise AssertionError(f"Process stopped at {result['stopped']}")
    if result["wall_seconds"] > case["timeout_seconds"]:
        raise AssertionError("Process exceeded the wall-clock limit")
    if not result["peak_rss_bytes"] or result["peak_rss_bytes"] >= MAX_RSS_BYTES:
        raise AssertionError("Peak RSS must be measured and below 500 MiB")
    if result["stdout_bytes"] + result["stderr_bytes"] > MAX_OUTPUT_BYTES:
        raise AssertionError("Combined output exceeds 1 MiB")
    if result["exit"] != case["exit"]:
        raise AssertionError(f"Expected exit {case['exit']}, got {result['exit']}")
    if result["stderr_bytes"] != 0:
        raise AssertionError("JSON resource cases must report diagnostics only in stdout")
    data = json.loads(result["stdout"])
    if (data["schema_version"] != 1 or data["command"] != case["command"]
            or data["status"] != ("ok" if case["exit"] == 0 else "diagnostics") or data["error"] is not None):
        raise AssertionError("Resource failures must retain the CLI diagnostic contract")
    codes = [item["code"] for item in data["diagnostics"]]
    if codes != case["codes"]:
        raise AssertionError(f"Wrong diagnostic codes/count: {len(codes)} entries, first={codes[:3]}, last={codes[-3:]}")
    if not codes and [flag["value"] for flag in data["flags"]] != ["-DGOOD=1"]:
        raise AssertionError("Invalid unrelated documents poisoned the valid query")
    sources = [Path(item["location"]["source"]).name for item in data["diagnostics"]]
    if sources != case["sources"]:
        raise AssertionError("Diagnostic provenance or first-occurrence ordering changed")
    if codes and codes[-1] == "PC021" and [item["location"]["line"] for item in data["diagnostics"]] != list(range(4, 105)):
        raise AssertionError("The diagnostic cap must preserve the first 100 errors and the next error location")
    if case["command"] == "check":
        if data["file_count"] != case["file_count"] or data["package_ids"] != case["package_ids"]:
            raise AssertionError("Directory checks omitted later valid entries or duplicate-counted failed packages")
    return {"status": data["status"], "diagnostic_count": len(codes),
            "diagnostic_codes": dict((code, codes.count(code)) for code in set(codes))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--target-dir", type=Path)
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("--report", type=Path, default=ROOT / "_build/verification/resource-limits.json")
    parser.add_argument("--worker", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if sys.platform != "linux" and os.name != "nt":
        parser.error("Resource measurements support Linux and Windows")
    if args.worker:
        print(json.dumps(measure(json.loads(args.worker.read_text(encoding="utf-8")))))
        return
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    temporary = ROOT / ".tmp"
    temporary.mkdir(exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix="resource-limits-", dir=temporary)).resolve()
    report = {"schema_version": 1, "passed": False, "platform": platform.platform(),
              "python": platform.python_version(), "workspace": str(workspace), "cases": [],
              "limits": {"wall_seconds_per_process": args.timeout, "peak_rss_bytes": MAX_RSS_BYTES,
                         "combined_output_bytes": MAX_OUTPUT_BYTES},
              "measurement": {"scope": "one native CLI process per fresh Python worker; build and worker excluded",
                              "wall_unit": "seconds", "memory_unit": "bytes", "mib_bytes": MIB,
                              "peak_method": "GetProcessMemoryInfo.PeakWorkingSetSize" if os.name == "nt"
                              else "getrusage(RUSAGE_CHILDREN).ru_maxrss multiplied by 1024 in a fresh worker",
                              "live_memory_guard": "PeakWorkingSetSize" if os.name == "nt" else "/proc/PID/status VmHWM"}}
    try:
        cli = args.cli.resolve() if args.cli else build_cli(args.moon, args.target_dir.resolve() if args.target_dir else workspace / "target")
        report["cli_sha256"] = hashlib.sha256(cli.read_bytes()).hexdigest()
        directories = fixtures(workspace)
        report["inputs"] = {name: [{"file": path.name, "bytes": path.stat().st_size,
                                   "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                                  for path in sorted(directory.glob("*.pc"))]
                            for name, directory in directories.items()}
        for shape, root, failed_codes, failed_source, all_sources, package_ids in (
                ("repeated-expansion", "cpu", ["PC009"], "cpu.pc", ["cpu.pc"], ["zz_good"]),
                ("many-diagnostics", "root", ["PC001"] * 100 + ["PC021"], "bad.pc", ["bad.pc"] * 101, ["root", "zz_good"]),
                ("many-documents", "f000", ["PC009"], "f000.pc", [f"f{i:03}.pc" for i in range(150)], ["zz_good"])):
            directory = directories[shape]
            for operation in ("unrelated-query", "failed-query", "directory-check"):
                is_check = operation == "directory-check"
                success = operation == "unrelated-query"
                expected_codes = [] if success else (["PC009"] * 150 if is_check and shape == "many-documents" else failed_codes)
                case = {"case": f"{shape}/{operation}", "command": "check" if is_check else "query",
                        "exit": 0 if success else 1, "codes": expected_codes,
                        "timeout_seconds": args.timeout,
                        "sources": [] if success else all_sources if is_check else [failed_source] * len(expected_codes),
                        "file_count": len(report["inputs"][shape]), "package_ids": package_ids}
                command = [str(cli), "check", str(directory), "--json"] if is_check else [
                    str(cli), "query", str(directory), "zz_good" if success else root,
                    "--cflags" if success else "--libs", "--json"]
                spec = workspace / "process.json"
                spec.write_text(json.dumps({"command": command, "cwd": str(workspace),
                                           "timeout_seconds": args.timeout}), encoding="utf-8")
                worker = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--worker", str(spec)],
                                        capture_output=True, text=True, encoding="utf-8", timeout=args.timeout + 15)
                row = {"case": case["case"], "passed": False, "command": command}
                report["cases"].append(row)
                try:
                    if worker.returncode:
                        raise AssertionError(f"Measurement worker failed: {worker.stderr}")
                    result = json.loads(worker.stdout)
                    row.update({key: value for key, value in result.items() if key not in ("stdout", "stderr")})
                    row.update(verify(case, result))
                    row["passed"] = True
                except (ValueError, KeyError, AssertionError) as error:
                    row["error"] = str(error)
                print(f"{case['case']}: passed={row['passed']}; wall={row.get('wall_seconds')}s; peak={row.get('peak_rss_bytes')} bytes", flush=True)
        if hashlib.sha256(cli.read_bytes()).hexdigest() != report["cli_sha256"]:
            raise AssertionError("CLI executable changed during verification")
        report["passed"] = all(row["passed"] for row in report["cases"])
    finally:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"CLI resource limits: passed={report['passed']}; {args.report}")
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
