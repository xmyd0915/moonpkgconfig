#!/usr/bin/env bash
# Build the published Cairo binding with its original build.js and native tests.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin" "$work/binding"
curl -fsSL --retry 3 --max-time 90 -o "$work/cairo.zip" \
  https://download.mooncakes.io/user/tonyfettes/cairo/0.2.0.zip
echo "8bbd90e19b485c9c5a084d3afa80a882c5c496793ef7cada1aff781939ec7fad  $work/cairo.zip" | sha256sum -c -
unzip -q "$work/cairo.zip" -d "$work/binding"
(cd "$work/binding" && sha256sum -- *) > "$work/sources.sha256"
(cd "$root" && moon install ./cmd/moonpkgconfig --bin "$work/bin")

# The upstream hook requests exactly these two queries. Keep the adapter local
# to the test process so all compiler flags come from the installed command.
export CAIRO_QUERY_LOG="$work/queries"
export CAIRO_PC_DIR="/usr/lib/$(cc -print-multiarch)/pkgconfig"
cat > "$work/bin/pkg-config" <<'SH'
#!/bin/sh
set -eu
test "$#" = 2 && test "$2" = cairo || exit 2
case "$1" in --cflags|--libs) ;; *) exit 2 ;; esac
mode=$1
set -- query "$CAIRO_PC_DIR" cairo "$mode"
for directory in /usr/lib/pkgconfig /usr/share/pkgconfig; do
  if test -d "$directory"; then set -- "$@" --path "$directory"; fi
done
moonpkgconfig "$@"
printf '%s\n' "$mode" >> "$CAIRO_QUERY_LOG"
SH
chmod +x "$work/bin/pkg-config"
export PATH="$work/bin:$PATH"
cd "$work/binding"
moon test --target native 2>&1 | tee "$work/tests.log"
grep -Fq 'Total tests: 7, passed: 7, failed: 0.' "$work/tests.log"
grep -Fxq -- '--cflags' "$CAIRO_QUERY_LOG"
grep -Fxq -- '--libs' "$CAIRO_QUERY_LOG"
sha256sum --check --quiet "$work/sources.sha256"
echo 'tonyfettes/cairo 0.2.0: compiler and linker queries used MoonPkgConfig; 7 native tests passed.'
