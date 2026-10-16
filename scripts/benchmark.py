"""Measure release-build workloads in fresh processes; no third-party packages."""

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys


def measure(binary, shape, size, operation, timeout):
    process = subprocess.Popen(
        [str(binary), shape, str(size), operation],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()
        return {"error": "timeout", "peak_rss_bytes": None}
    peak = None
    if os.name == "nt":
        from ctypes import wintypes

        class Counters(ctypes.Structure):
            _fields_ = [
                ("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                *[(name, ctypes.c_size_t) for name in (
                    "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
                    "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage",
                    "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage",
                )],
            ]

        counters = Counters()
        counters.cb = ctypes.sizeof(counters)
        get_info = ctypes.WinDLL("psapi").GetProcessMemoryInfo
        get_info.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
        get_info.restype = wintypes.BOOL
        if get_info(wintypes.HANDLE(int(process._handle)), ctypes.byref(counters), counters.cb):
            peak = counters.PeakWorkingSetSize
    else:
        import resource
        peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        if sys.platform != "darwin":
            peak *= 1024
    if process.returncode:
        return {"error": f"exit {process.returncode}: {stderr.strip()[:300]}", "peak_rss_bytes": peak}
    result = json.loads(stdout)
    result["peak_rss_bytes"] = peak
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--sizes", type=int, nargs="+", default=[100, 500, 1000])
    parser.add_argument("--shapes", nargs="+", default=["chain", "wide", "shared", "virtual"])
    parser.add_argument("--operations", nargs="+", default=["load", "resolve", "cflags", "path-last", "paths", "check"])
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--allow-failures", action="store_true")
    parser.add_argument("--worker", nargs=3, metavar=("SHAPE", "SIZE", "OPERATION"), help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.binary.is_file() or args.repeat < 1 or args.timeout <= 0:
        parser.error("binary must exist; repeat and timeout must be positive")
    if args.worker:
        shape, size, operation = args.worker
        print(json.dumps(measure(args.binary.resolve(), shape, int(size), operation, args.timeout)))
        return
    results = []
    for shape in args.shapes:
        for size in args.sizes:
            for operation in args.operations:
                samples = []
                for _ in range(args.repeat):
                    output = subprocess.check_output([
                        sys.executable, str(Path(__file__).resolve()), "--binary", str(args.binary.resolve()),
                        "--timeout", str(args.timeout), "--worker", shape, str(size), operation,
                    ], text=True)
                    samples.append(json.loads(output))
                    if "error" in samples[-1]:
                        break
                row = {"shape": shape, "size": size, "operation": operation, "samples": samples}
                if "error" in samples[-1]:
                    row["error"] = samples[-1]["error"]
                    print(f"{shape:7} {size:5} {operation:9} FAILED: {row['error']}", flush=True)
                else:
                    row["median_us"] = statistics.median(s["elapsed_us"] for s in samples)
                    peaks = [s["peak_rss_bytes"] for s in samples if s["peak_rss_bytes"] is not None]
                    row["peak_rss_bytes"] = max(peaks) if peaks else None
                    print(f"{shape:7} {size:5} {operation:9} {row['median_us']:12.1f} us; peak RSS {row['peak_rss_bytes']}", flush=True)
                results.append(row)
    report = {
        "platform": platform.platform(), "python": platform.python_version(),
        "repeat": args.repeat, "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
        "clock_unit": "microseconds", "peak_rss_scope": "entire fresh workload process",
        "results": results,
    }
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if any("error" in row for row in results) and not args.allow_failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
