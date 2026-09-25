#!/usr/bin/env sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

printf '%s\n' '1/4 Explain where compiler flags come from'
moon run --target native cmd/query examples/valid imagekit --cflags --explain

printf '%s\n' '2/4 Check that invalid metadata is rejected with diagnostics'
set +e
invalid_output=$(moon run --target native cmd/check examples/invalid 2>&1)
invalid_status=$?
set -e
printf '%s\n' "$invalid_output"
test "$invalid_status" -eq 1
printf '%s\n' "$invalid_output" | grep -q '4 diagnostics.'

printf '%s\n' '3/4 Apply an explicit cross-compilation sysroot'
sysroot_output=$(moon run --target native cmd/query examples/path-policy paths --cflags --sysroot=/sdk)
printf '%s\n' "$sysroot_output"
test "$sysroot_output" = '-I/sdk/usr/include -I/sdk/opt/include -isystem /sdk/usr/include/system -DKEEP=1'

printf '%s\n' '4/4 Resolve and reject two versioned virtual dependencies'
moon run --target native cmd/query examples/provides bar-new --path testdata/pkgconf-3.0.7 --exists
set +e
moon run --target native cmd/query examples/provides bar-old --path testdata/pkgconf-3.0.7 --exists >/dev/null 2>&1
provides_status=$?
set -e
test "$provides_status" -eq 1

printf '%s\n' 'Reviewer walkthrough: passed'
