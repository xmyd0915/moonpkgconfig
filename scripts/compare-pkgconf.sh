#!/usr/bin/env sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

reference=${PKGCONF:-pkgconf}
if ! command -v "$reference" >/dev/null 2>&1; then
  echo "pkgconf reference tool not found: $reference" >&2
  exit 2
fi

export PKG_CONFIG_PATH="$project_root/examples/valid"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"

assert_equal() {
  label=$1
  # pkgconf versions differ on whether a display line ends in one space.
  # Keep argument contents and order strict while ignoring only line-end space.
  expected=$(printf '%s' "$2" | sed 's/[[:space:]]*$//')
  actual=$(printf '%s' "$3" | sed 's/[[:space:]]*$//')
  if [ "$actual" != "$expected" ]; then
    echo "$label differs" >&2
    echo "pkgconf:      $expected" >&2
    echo "MoonPkgConfig: $actual" >&2
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      echo "::error title=pkgconf differential::$label differs; pkgconf=$expected; MoonPkgConfig=$actual"
    fi
    exit 1
  fi
}

assert_equal "Cflags" \
  "$("$reference" --cflags imagekit)" \
  "$(moon run --target native cmd/query examples/valid imagekit --cflags)"
assert_equal "dynamic Libs" \
  "$("$reference" --libs imagekit)" \
  "$(moon run --target native cmd/query examples/valid imagekit --libs --dedupe-paths)"
assert_equal "static Libs" \
  "$("$reference" --static --libs imagekit)" \
  "$(moon run --target native cmd/query examples/valid imagekit --libs --static --dedupe-paths)"
assert_equal "module version" \
  "$("$reference" --modversion imagekit)" \
  "$(moon run --target native cmd/query examples/valid imagekit --modversion)"
assert_equal "variable" \
  "$("$reference" --variable=prefix imagekit)" \
  "$(moon run --target native cmd/query examples/valid imagekit --variable=prefix)"
assert_equal "overridden variable" \
  "$("$reference" --define-variable=prefix=/custom --variable=prefix imagekit)" \
  "$(moon run --target native cmd/query examples/valid imagekit --variable=prefix --define-variable=prefix=/custom)"
assert_equal "overridden Cflags" \
  "$("$reference" --define-variable=prefix=/custom --cflags imagekit)" \
  "$(moon run --target native cmd/query examples/valid imagekit --cflags --define-variable=prefix=/custom)"

export PKG_CONFIG_PATH="$project_root/examples/order"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
assert_equal "diamond Cflags order" \
  "$("$reference" --cflags root)" \
  "$(moon run --target native cmd/query examples/order root --cflags)"
assert_equal "private dependency order" \
  "$("$reference" --static --libs root)" \
  "$(moon run --target native cmd/query examples/order root --libs --static)"

export PKG_CONFIG_PATH="$project_root/testdata/real-world"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
assert_equal "zlib template Cflags" \
  "$("$reference" --cflags zlib)" \
  "$(moon run --target native cmd/query testdata/real-world zlib --cflags)"
assert_equal "zlib template Libs" \
  "$("$reference" --libs zlib)" \
  "$(moon run --target native cmd/query testdata/real-world zlib --libs)"
assert_equal "libffi template Cflags" \
  "$("$reference" --cflags libffi)" \
  "$(moon run --target native cmd/query testdata/real-world libffi --cflags)"
assert_equal "libffi template Libs" \
  "$("$reference" --libs libffi)" \
  "$(moon run --target native cmd/query testdata/real-world libffi --libs)"

export PKG_CONFIG_PATH="$project_root/examples/path-policy"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
export PKG_CONFIG_SYSTEM_INCLUDE_PATH=/usr/include
export PKG_CONFIG_SYSTEM_LIBRARY_PATH=/usr/lib
unset PKG_CONFIG_SYSROOT_DIR || true
assert_equal "system Cflags filtering" \
  "$("$reference" --cflags paths)" \
  "$(moon run --target native cmd/query examples/path-policy paths --cflags --system-include-path=/usr/include)"
assert_equal "system Libs filtering" \
  "$("$reference" --libs paths)" \
  "$(moon run --target native cmd/query examples/path-policy paths --libs --system-library-path=/usr/lib)"
export PKG_CONFIG_SYSROOT_DIR=/sdk
assert_equal "sysroot Cflags" \
  "$("$reference" --cflags paths)" \
  "$(moon run --target native cmd/query examples/path-policy paths --cflags --sysroot=/sdk --system-include-path=/usr/include)"
assert_equal "sysroot Libs" \
  "$("$reference" --libs paths)" \
  "$(moon run --target native cmd/query examples/path-policy paths --libs --sysroot=/sdk --system-library-path=/usr/lib)"
unset PKG_CONFIG_SYSROOT_DIR

compare_status() {
  label=$1
  reference_option=$2
  moon_option=$3
  set +e
  "$reference" "$reference_option" imagekit >/dev/null 2>&1
  reference_status=$?
  moon run --target native cmd/query examples/valid imagekit "$moon_option" >/dev/null 2>&1
  moon_status=$?
  set -e
  if [ "$moon_status" -ne "$reference_status" ]; then
    echo "$label exit status differs: pkgconf=$reference_status MoonPkgConfig=$moon_status" >&2
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      echo "::error title=pkgconf differential::$label exit status differs; pkgconf=$reference_status; MoonPkgConfig=$moon_status"
    fi
    exit 1
  fi
}

export PKG_CONFIG_PATH="$project_root/examples/valid"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
compare_status "minimum version match" --atleast-version=1.1 --atleast-version=1.1
compare_status "maximum version mismatch" --max-version=1.1 --max-version=1.1
compare_status "exact version match" --exact-version=1.2.0 --exact-version=1.2.0

compare_provider_status() {
  package=$1
  set +e
  "$reference" --exists "$package" >/dev/null 2>&1
  reference_status=$?
  moon run --target native cmd/query examples/provides "$package" --path testdata/pkgconf-3.0.7 --exists >/dev/null 2>&1
  moon_status=$?
  set -e
  if [ "$moon_status" -ne "$reference_status" ]; then
    echo "Provides $package exit status differs: pkgconf=$reference_status MoonPkgConfig=$moon_status" >&2
    exit 1
  fi
}

export PKG_CONFIG_PATH="$project_root/examples/provides:$project_root/testdata/pkgconf-3.0.7"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
compare_provider_status bar-new
compare_provider_status bar-old

echo "pkgconf differential checks: 22 passed (reference $("$reference" --version))"
