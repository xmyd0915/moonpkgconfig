#!/usr/bin/env python3
"""Copy the self-contained consumer and verify its actual MoonCakes dependency."""

import argparse
from pathlib import Path
import shutil
import sys
import tempfile

from native_ffi import ROOT, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pc-dir", type=Path, required=True)
    parser.add_argument("--path", type=Path, action="append", default=[])
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--cc")
    parser.add_argument("--msvc-lib", action="append", default=[])
    args = parser.parse_args()
    # Place the copy outside the checkout. It must resolve the published module,
    # with no parent source tree or moon.work supplying a local replacement.
    working = Path(tempfile.mkdtemp(prefix="pc-consumer-"))
    consumer = working / "consumer"
    shutil.copytree(ROOT / "examples/zlib-consumer", consumer,
                    ignore=shutil.ignore_patterns("_build", ".mooncakes", "__pycache__"))
    command = [sys.executable, str(consumer / "build.py"), "--demo", "--moon", args.moon,
               "--pc-dir", str(args.pc_dir.resolve())]
    for path in args.path:
        command.extend(["--path", str(path.resolve())])
    if args.cc:
        command.extend(["--cc", args.cc])
    for mapping in args.msvc_lib:
        command.extend(["--msvc-lib", mapping])
    print(run(command, consumer), flush=True)
    print(f"Independent registry consumer: {consumer}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError) as error:
        raise SystemExit(str(error))
