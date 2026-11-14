# MoonPkgConfig

[中文](README.md) · [CI](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml) · [MoonCakes](https://mooncakes.io/docs/xmyd0915/moonpkgconfig) · [Downloads](https://github.com/xmyd0915/moonpkgconfig/releases/tag/v0.4.0) · [Release notes](docs/release-notes-0.4.0.md)

A `pkg-config` metadata engine written in MoonBit for native FFI, build tools and CI. It parses `.pc` files, resolves dependencies, computes compiler/linker arguments, and explains each argument's package, field, source location and dependency path.

The pure MoonBit core supports wasm, wasm-gc, JavaScript and native. Parsing and queries do not invoke a shell or an external `pkg-config` command.

| Task | Entry point |
| --- | --- |
| Parse metadata or calculate arguments in MoonBit | `moon add xmyd0915/moonpkgconfig@0.4.0` |
| Inspect files or integrate an external build tool | `moonpkgconfig inspect / query / check`, with JSON output |
| Build a native application | [zlib, Expat and file-compression template](examples/native-consumer/README.md) |
| Integrate an existing multi-package project | [Experimental pre-build integration](examples/project-integration/README.md) |

Version 0.4.0 adds the unified CLI and versioned JSON, fixes shared-dependency linker ordering, and improves file diagnostics, private-dependency validation and parser resource limits. See the [upgrade notes](docs/release-notes-0.4.0.md) and [release records](docs/release.md).

## Install and try the CLI

Source builds use `moonc 0.10.20+65efd5b93`, `moon 0.1.20261104`, and a native C toolchain. After installing [MoonBit](https://www.moonbitlang.com/download/):

```sh
git clone https://github.com/xmyd0915/moonpkgconfig.git
cd moonpkgconfig
moon update
moon install ./cmd/moonpkgconfig
moonpkgconfig query examples/valid imagekit --libs --static --json --explain
moonpkgconfig inspect examples/valid/imagekit.pc --json
moonpkgconfig check examples/invalid --json
```

The last command checks deliberately invalid inputs and exits with code 1. Add the installation directory to PATH, or specify it with `moon install ./cmd/moonpkgconfig --bin <directory>`. The installed command works outside the repository; each subcommand supports `--help`.

To run without installing MoonBit, use a packaged Linux or Windows executable. Download locations, supported platforms, licenses and checksum instructions are in the [CLI download guide](docs/cli-download.md).

For your own native installation, pass its `.pc` directory and package identifier explicitly:

```sh
moonpkgconfig query /path/to/sdk/lib/pkgconfig zlib --modversion
moonpkgconfig query /path/to/sdk/lib/pkgconfig zlib --cflags
moonpkgconfig query /path/to/sdk/lib/pkgconfig zlib --libs --static --explain
moonpkgconfig check /path/to/sdk/lib/pkgconfig --path /path/to/extra/pkgconfig --json
```

Directories are searched in command-line order; the first file with a given name takes precedence. `--explain` shows argument origins and dependency paths. Use `--json` for programmatic integration and intact argument boundaries.

## Use the library

Run `moon add xmyd0915/moonpkgconfig@0.4.0` in an existing module and add this test import to `moon.pkg` for the example below:

```moonbit
import {
  "xmyd0915/moonpkgconfig" @pc,
} for "test"
```

Save this runnable example as `example_test.mbt` and run `moon test`:

```moonbit
test "query a native library" {
  let input =
    #|Name: codec
    #|Description: Example native library
    #|Version: 1.0
    #|Libs: -lcodec
    #|Libs.private: -lm
  let document = @pc.parse(input, source="codec.pc")
  let packages = @pc.PackageSet::new()
  assert_true(packages.add("codec", document).is_empty())
  let result = packages.collect_libs("codec", static_linking=true)
  assert_true(result.diagnostics.is_empty())
  assert_eq(result.flags[0].value, "-lcodec")
  assert_eq(result.flags[1].value, "-lm")
  assert_eq(result.flags[1].field, "Libs.private")
  assert_eq(result.flags[1].location.source, "codec.pc")
}
```

`parse` retains raw text, expanded values and locations. `PackageSet` resolves public/private dependencies, version constraints, conflicts and virtual providers. `collect_cflags` and `collect_libs` return arguments with origins; `dependency_paths` supplies shortest dependency paths. `PackageSet::select` validates a selected package without traversing dependencies, for metadata queries.

The core accepts in-memory documents and does not access the filesystem. See the [published API](https://mooncakes.io/docs/xmyd0915/moonpkgconfig).

## Call from a build tool

```python
import json
import subprocess

result = subprocess.run(
    ["moonpkgconfig", "query", "./pkgconfig", "example", "--libs", "--json"],
    capture_output=True, text=True, encoding="utf-8", check=False,
)
report = json.loads(result.stdout)
if result.returncode != 0 or report["schema_version"] != 1 or report["status"] != "ok":
    raise RuntimeError(report)
arguments = [flag["value"] for flag in report["flags"]]
```

Pass `arguments` as an argv list to the compiler; do not evaluate or split shell text again. JSON is written to stdout; keep stderr separate. Text failures write diagnostics to stderr and leave stdout empty for failed flag queries. See the complete [JSON contract](docs/cli-json.md).

| Exit code | Meaning |
| --- | --- |
| `0` | Success or a satisfied version predicate |
| `1` | Metadata/per-file diagnostics, a missing variable, or an unsatisfied predicate |
| `2` | Usage error, search-directory IO error, or direct inspect file IO error |

Predicates and all CLI flag queries validate public and private dependencies. Dynamic `--libs` still emits only public linker arguments. `--modversion` and `--variable=name` validate only the selected root. Unrelated broken files do not block a valid package query; the first broken file still retains precedence over later files with the same name.

## Native applications

The [native consumer template](examples/native-consumer/README.md) uses one MoonBit planner and build adapter for zlib, Expat and a file-compression tool. It reads installed `.pc` files, reports dependency errors, and builds the application from the resulting arguments after repair. From the repository root:

```sh
python scripts/review-native.py
```

This prepares fixed static library versions, runs consumers outside the repository, checks file interoperability with Python zlib, and prints the executable path. Requirements: Python 3.9+, CMake 3.15+, a C compiler and `make` on Linux, or Visual Studio C++ tools and the Windows SDK on Windows. See the [native walkthrough](docs/native-walkthrough.md) for dependency versions, existing-installation options and platform limits.

The [multi-package example](examples/project-integration/README.md) preserves existing package configuration and connects native libraries to ordinary `moon build/run/test` through an experimental pre-build hook. Run `python scripts/verify-project-integration.py` to reproduce it. The hook is tied to the pinned toolchain. The [libpng → zlib example](examples/libpng-ffi/README.md) separately exercises private dependencies and PNG pixel round trips on Ubuntu.

## Verify and develop

```sh
moon version --all
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
python scripts/verify-cli.py
python scripts/verify-install.py --package
```

[GitHub Actions](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml) checks, builds and tests all four targets on Ubuntu and Windows, verifies an installed CLI and actual source archives, and runs native applications. Compatibility checks use pinned pkgconf 3.0.7 with upstream samples, six project templates, seeded inputs, installed system metadata and copies with dependencies removed. Real static libraries are compiled, linked and executed separately.

Commands, tool versions and results for each source revision are recorded in the [development guide](DEVELOPMENT.md), [verification records](docs/verification.md), [compatibility guide](docs/compatibility.md) and [performance notes](docs/query-performance.md).

## Scope

- Supports UTF-8, LF/CRLF, a leading BOM, comments, continuations and ordered variable expansion. Known field names accept ASCII case variants while retaining original spelling and locations; variables and unknown extension fields remain case-sensitive.
- Supports version constraints, `Provides`, `Conflicts`, private dependencies, static fields and five argument classifications. `Cflags.private` is included only for static queries.
- Duplicate definitions, undefined variables and dependency cycles are strict errors. CLI roots accept one package identifier, not a version expression.
- Expansion is capped at 1,048,576 UTF-16 code units both per value and cumulatively per document. The first `PC009` stops parsing. The parser keeps the first 100 diagnostics, then emits `PC021` and stops if another occurs. These limits do not bound input-file size or total process memory.
- Search directories, sysroot and system-path filters are explicit; `PKG_CONFIG_*` environment variables are not read. Paths already under the sysroot are not prefixed again.
- Locations identify the starting physical line of a logical line and Unicode columns after continuation/comment processing, not exact physical spans inside continuations.
- Full pkgconf compatibility, automatic Windows relocation and complete fragment deduplication are outside the current scope. Native examples translate only explicitly supported compiler options and reject unknown options.

MoonPkgConfig uses the [MIT license](LICENSE). Fixed upstream samples, versions, origins and their licenses are documented in [ORIGINS.md](ORIGINS.md). Future work is listed in the [roadmap](ROADMAP.md).
