#!/usr/bin/env python3
"""Build a native MoonBit consumer using flags queried from an installed zlib.pc."""

import json
import sys

from native_ffi import arguments, build_example, query, values

SUCCESS = "MoonBit zlib FFI: CRC-32, 3 round trips and 3 error cases passed"


def main():
    moon, compiler, directories = arguments(__doc__)
    if not (directories[0] / "zlib.pc").is_file():
        raise RuntimeError(f"no installed zlib.pc in {directories[0]}")
    version = query(moon, directories, "zlib", "--modversion")
    cflags = query(moon, directories, "zlib", "--cflags")
    libs = query(moon, directories, "zlib", "--libs", static=True)
    print(f"Installed zlib: {version}")
    print(f"Cflags from MoonPkgConfig: {json.dumps(values(cflags))}")
    print(f"Static Libs from MoonPkgConfig: {json.dumps(values(libs))}")
    build_example(moon, compiler, "zlib-ffi", "zlib_stub.c", cflags, libs, SUCCESS)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
