"""Run graph and expansion correctness workloads without timing thresholds."""

from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
moon = shutil.which("moon")
if moon is None:
    raise RuntimeError("MoonBit CLI must be installed")
subprocess.run([moon, "build", "--target", "native", "--release", "cmd/benchmark"], cwd=ROOT, check=True)
directory = ROOT / "_build/native/release/build/cmd/benchmark"
binary = next((path for path in [directory / "benchmark.exe", directory / "benchmark"] if path.is_file()), None)
if binary is None:
    raise RuntimeError("Native benchmark executable was not produced")
command = [sys.executable, str(ROOT / "scripts/benchmark.py"), "--binary", str(binary), "--repeat", "1"]
for options in [
    ["--sizes", "1000", "--operations", "resolve", "cflags", "paths", "check", "--output", ".tmp/performance-smoke.json"],
    ["--sizes", "5000", "--shapes", "chain", "--operations", "resolve", "path-last", "check"],
    ["--sizes", "1000", "--shapes", "broken", "--operations", "check"],
    ["--sizes", "1048575", "1048576", "1048577", "--shapes", "expansion", "--operations", "expand-variable", "expand-literal"],
]:
    subprocess.run([*command, *options], cwd=ROOT, check=True)
print("Graph and expansion workloads: passed (timings reported, no speed threshold)")
