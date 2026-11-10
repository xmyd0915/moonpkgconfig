# MoonPkgConfig

[中文](README.md) · [CI](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml) · [MoonCakes](https://mooncakes.io/docs/xmyd0915/moonpkgconfig)

A source-aware `pkg-config` metadata engine written in MoonBit. It parses `.pc` files, resolves dependencies, computes compiler/linker arguments, and explains each argument's package, field and source location. The pure MoonBit core does not invoke a shell or an external `pkg-config` command.

## Choose an entry point

| Use case | Entry point |
| --- | --- |
| Import the published core in MoonBit | `moon add xmyd0915/moonpkgconfig` (published version: 0.3.1) |
| Inspect metadata or integrate an external build tool | Install the current checkout CLI, or download a verified CI package |
| Build a native FFI consumer | [Published-package template](examples/native-consumer/README.md) |
| Keep an existing multi-package project's build settings | [Experimental pre-build integration](examples/project-integration/README.md) |

The unified CLI and experimental project integration are main-branch additions. They have not been published as a new MoonCakes release. Examples are maintained by this project and do not represent independent adoption.

## Try the CLI

Use the pinned `moonc 0.10.16+b1a0e846e` / `moon 0.1.20261020` toolchain to reproduce CI:

```sh
git clone https://github.com/xmyd0915/moonpkgconfig.git
cd moonpkgconfig
moon update
moon install ./cmd/moonpkgconfig
moonpkgconfig query examples/valid imagekit --libs --static --json --explain
moonpkgconfig query examples/valid imagekit --modversion --json
moonpkgconfig inspect examples/valid/imagekit.pc --json
moonpkgconfig check examples/invalid --json
```

Add the installation directory to PATH, or use `moon install ./cmd/moonpkgconfig --bin <directory>` and invoke the executable by its full path. The last command deliberately checks invalid inputs and exits with code 1.

To try the CLI without a MoonBit installation, download `ubuntu-cli-package` or `windows-cli-package` from a successful [workflow run](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml). GitHub requires sign-in and repository read access for artifact downloads ([GitHub instructions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)). Artifacts are retained for 30 days. Unpack the outer artifact, verify the CLI ZIP against its `.zip.sha256` file, then extract it. On Linux, use `chmod +x moonpkgconfig` if needed. Invoke `./moonpkgconfig --help` or `.\moonpkgconfig.exe --help` on Windows.

The package includes the executable, MIT license, dependency notices, usage instructions, build information and file checksums. Check the full source commit, platform and architecture in `build-info.json`. Linux packages are verified on the corresponding Ubuntu CI environment, not every Linux distribution or libc version. These are CI builds, not permanent release assets. Detailed commands: [download and verification](docs/cli-download.md).

## Machine-readable output

For recognized `inspect`, `query` and `check` commands, `--json` returns one JSON object on stdout for success, diagnostics, usage errors and IO errors. Keep stderr separate. Help takes precedence and remains text.

- Exit 0: success or a satisfied predicate.
- Exit 1: metadata diagnostics, a missing variable, or an unsatisfied version predicate.
- Exit 2: usage or filesystem error.

Check `schema_version` (currently 1), `status` and the exit code. Query reports retain `flags` and `diagnostics`; inspect reports retain `entries` and `diagnostics`. Additional fields describe errors and query context. Metadata queries return `value`; evaluated predicates return `matched`. `--json --explain` adds `paths`, a mapping from each returned argument's package to its dependency path. See the complete [JSON contract](docs/cli-json.md).

```python
import json
import subprocess

result = subprocess.run(
    ["moonpkgconfig", "query", "./pkgconfig", "example", "--libs", "--json"],
    capture_output=True, text=True, encoding="utf-8", check=False,
)
report = json.loads(result.stdout)
if result.returncode != 0 or report["schema_version"] != 1:
    raise RuntimeError(report)
arguments = [flag["value"] for flag in report["flags"]]
```

Pass arguments to subprocesses as an argv list. The text flag output uses POSIX shell quoting; it is not a Windows command string. Search directories, sysroot and system-path filtering are explicit, so queries do not silently depend on the host's `PKG_CONFIG_*` environment.

## Scope and verification

The core supports ordered variable expansion, public/private dependencies, version constraints, virtual providers, static flags, source diagnostics and argument classification. It is intentionally strict about duplicate definitions and undefined variables. It does not claim full `pkgconf` compatibility, automatic Windows relocation, or arbitrary compiler-option translation in the native examples.

CI checks, builds and tests the core on wasm, wasm-gc, JavaScript and native, verifies the actual package archive and published 0.3.1 in fresh consumers, and builds real zlib/Expat consumers on Ubuntu and Windows. CLI verification runs an installed executable outside the repository; standalone-package verification extracts and runs the actual ZIP with MoonBit environment variables and PATH cleared.

```sh
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
python scripts/verify-cli.py
python scripts/package-cli.py
```

See [verification records](docs/verification.md), [compatibility scope](docs/compatibility.md), [development instructions](DEVELOPMENT.md), and [upstream origins and licenses](ORIGINS.md). MoonPkgConfig is available under the [MIT license](LICENSE).
