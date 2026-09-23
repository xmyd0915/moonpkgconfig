#!/usr/bin/env sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

build_dir=examples/native/build
mkdir -p "$build_dir"

cc -Iexamples/native/include -c examples/native/src/moonpkg_demo.c -o "$build_dir/moonpkg_demo.o"
ar rcs "$build_dir/libmoonpkg_demo.a" "$build_dir/moonpkg_demo.o"

cflags=$(moon run --target native cmd/query examples/native moonpkg-demo --cflags)
libs=$(moon run --target native cmd/query examples/native moonpkg-demo --libs)

# The query command emits a POSIX-shell-safe fragment. Inputs here are the
# repository's fixed demonstration file, not untrusted external metadata.
eval "c++ -std=c++17 examples/native/demo.cpp $cflags $libs -o $build_dir/demo"

test "$("$build_dir/demo")" = "MoonPkgConfig native demo: 42"
echo "Native C/C++ integration: passed"
