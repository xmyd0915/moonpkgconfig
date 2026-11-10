#!/usr/bin/env python3
"""Bootstrap a separate registry planner before ordinary MoonBit builds."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil

from adapter import DEPENDENCY, NAME, ROOT, digest, planner_sources, read_bindings, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "app")
    parser.add_argument("--pc-dir", type=Path, action="append", required=True)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--msvc-lib", action="append", default=[])
    args = parser.parse_args()
    project = args.project.resolve()
    read_bindings(project)
    directories = [str(path.resolve()) for path in args.pc_dir]
    if not all(Path(path).is_dir() for path in directories):
        parser.error("Every metadata search directory must exist")
    mappings = {}
    for value in args.msvc_lib:
        name, separator, library = value.partition("=")
        if os.name != "nt" or not separator or not re.fullmatch(NAME, name) or not re.fullmatch(NAME + r"\.lib", library) or name in mappings:
            parser.error("--msvc-lib requires a unique NAME=FILE.lib mapping on Windows")
        mappings[name] = library
    moon = shutil.which(args.moon)
    if not moon:
        parser.error("MoonBit executable not found")
    moon = str(Path(moon).resolve())
    for parent in (ROOT, *ROOT.parents, project, *project.parents):
        if (parent / "moon.work").exists():
            parser.error("This registry example must run outside moon.work overrides")
    destination = project / "_build/native-config.json"
    destination.parent.mkdir(exist_ok=True)
    # Once bootstrap starts, its failure cannot retain a successful old setup.
    destination.write_text('{"configured": false}\n', encoding="utf-8")
    planner = ROOT / "planner"
    run([moon, "update"], planner)
    run([moon, "build", "--target", "native", "--deny-warn", "."], planner)
    installed = planner / ".mooncakes/xmyd0915/moonpkgconfig/moon.mod"
    if not re.search(r'^version\s*=\s*"0\.3\.1"', installed.read_text(encoding="utf-8"), re.MULTILINE):
        raise RuntimeError("The planner must use published MoonPkgConfig 0.3.1")
    binaries = [planner / "_build/native/debug/build" / name for name in ("native-planner.exe", "native-planner")]
    binaries = [path for path in binaries if path.is_file()]
    if len(binaries) != 1:
        raise RuntimeError(f"Expected one planner executable, found {binaries}")
    data = {"configured": True, "dependency": DEPENDENCY, "planner": str(binaries[0]),
            "planner_sha256": digest(binaries[0]), "planner_sources": planner_sources(),
            "pc_directories": directories, "msvc_libraries": mappings}
    destination.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Configured {project}; use ordinary moon build/run/test --target native")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        raise SystemExit(str(error))
