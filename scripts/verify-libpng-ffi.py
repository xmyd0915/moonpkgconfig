#!/usr/bin/env python3
"""Verify a real libpng -> zlib dependency graph and run a MoonBit PNG consumer."""

import json
from pathlib import Path
import shutil
import sys

from native_ffi import (
    ROOT, arguments, build_example, query, query_command, run,
    temporary_directory, values,
)


PACKAGE = "libpng16"
SUCCESS = "MoonBit libpng FFI: 3 RGBA round trips and 4 error cases passed"


def main():
    moon, compiler, directories = arguments(__doc__)
    root_pc = directories[0] / (PACKAGE + ".pc")
    if not root_pc.is_file():
        raise RuntimeError(f"no installed {PACKAGE}.pc in {directories[0]}")
    version = query(moon, directories, PACKAGE, "--modversion")
    cflags = query(moon, directories, PACKAGE, "--cflags")
    dynamic = query(moon, directories, PACKAGE, "--libs")
    static = query(moon, directories, PACKAGE, "--libs", static=True)
    if any(flag["package"] == "zlib" for flag in dynamic):
        raise RuntimeError("dynamic Libs unexpectedly included the private zlib dependency")
    if not all(any(flag["package"] == "zlib" for flag in flags) for flags in (cflags, static)):
        raise RuntimeError("Cflags and static Libs must include the private zlib dependency")
    print(f"Installed libpng: {version}")
    print(f"Cflags: {json.dumps(values(cflags))}")
    print(f"Dynamic Libs: {json.dumps(values(dynamic))}")
    print(f"Static Libs: {json.dumps(values(static))}")

    # Copy the actual root metadata unchanged into an isolated search directory.
    # Its absolute prefix still points at the installed library, but no zlib.pc
    # can be discovered implicitly. Dynamic Libs remain valid; Cflags/static fail.
    with temporary_directory("libpng-missing-private-") as name:
        isolated = Path(name)
        shutil.copyfile(root_pc, isolated / root_pc.name)
        query(moon, [isolated], PACKAGE, "--libs")
        for mode, static_link in (("--cflags", False), ("--libs", True)):
            command = query_command(moon, [isolated], PACKAGE, mode, static_link)
            result = json.loads(run(command, ROOT, expected_status=1))
            if not any(
                problem["code"] == "PC015" and "zlib" in problem["message"]
                for problem in result["diagnostics"]
            ):
                raise RuntimeError("missing private zlib dependency was not diagnosed")
    print("Private dependency isolation: dynamic query passed; Cflags/static rejected missing zlib")
    build_example(moon, compiler, "libpng-ffi", "png_stub.c", cflags, static, SUCCESS)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
