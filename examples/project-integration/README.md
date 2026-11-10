# Existing project integration (experimental)

This example keeps a multi-package application's `moon.pkg` files intact while
MoonPkgConfig supplies native compiler arguments and propagates link arguments
from library packages to their users. A zlib-only command and a combined
zlib/Expat command use the same two library packages, which also have native tests.
The applications are maintained here; they are not third-party adoption claims.

The adapter uses MoonBit's [experimental prebuild configuration hook](https://docs.moonbitlang.com/en/stable/toolchain/moon/module.html#experimental-pre-build-config-script).
Its interface may change. This integration is tested with MoonBit
`0.10.16+b1a0e846e` and the accompanying `moon 0.1.20261020`.
It requires Python 3.9+, installed static zlib and Expat with their `.pc` files,
and the platform's native compiler. Windows uses x64 MSVC with the static CRT.

## Run

Copy this entire directory outside the repository. From the copy, bootstrap the
planner once (use `python3` where that is your Python command):

```sh
python configure.py --pc-dir /path/to/zlib/lib/pkgconfig --pc-dir /path/to/expat/lib/pkgconfig
moon -C app build --target native
moon -C app test --target native
moon -C app run --target native cmd/checksum
moon -C app run --target native cmd/combined
```

For Windows CMake zlib, its `.pc` directory is usually `share/pkgconfig`; also
pass `--msvc-lib z=zlibstatic.lib` to `configure.py`. Use correctly quoted paths
in upstream `.pc` flag fields when the installation path contains spaces.
The commands print `crc=3421780262 custom=7` and
`crc=3421780262 xml=true custom=7,11`. The custom numbers come from flags already
present in the library manifests, and are checked by C code and MoonBit tests.

From the repository root, a single verification command prepares fixed native
libraries and runs the complete sequence:

```sh
python scripts/verify-project-integration.py
```

To reuse dependencies from the existing native walkthrough:

```sh
python scripts/verify-project-integration.py --prepared-report _build/verification/native-walkthrough.json
```

The verifier also accepts `--zlib-pc-dir`, `--expat-pc-dir`, `--msvc-lib`, `--moon`,
and preparation options `--cmake`, `--cc`, `--zlib-archive`, `--expat-archive`.
The report is `_build/verification/project-integration.json`.

## Adapt an existing application

Keep your package layout, imports, native stubs, custom macros and other settings.
Copy `adapter.py`, `configure.py` and `planner/` beside the application, and put
the small `app/build.py` entry in the application root. Add the hook declaration
from `app/moon.mod` to your module. In `native-packages.json`, map each complete
MoonBit library package name to its `.pc` identifier, static mode and build
variable. In the corresponding manifest, append `${build.YOUR_VARIABLE}` to
the existing `stub-cc-flags`. The example's `${build.PC_RUNTIME}` adds Windows
`/utf-8 /MT`; use a compatible runtime for your installed libraries.

Run `configure.py --project /path/to/application --pc-dir ...` before building.
For this layout, the application must be a sibling of `planner/`, as in the
example, so its hook can import the adapter from its parent. The planner itself
is an independent module fixed to published MoonCakes MoonPkgConfig 0.3.1.
It has no prebuild hook. Only configuration builds it; application hooks invoke
the compiled planner directly, never `moon build`, so they cannot recursively
build their own module. Registry access is needed during bootstrap. This example
rejects `moon.work` overrides to keep that published-package evidence explicit.

Every ordinary build invocation rereads the explicit `.pc` directories and
recomputes the plan. No flag plan is cached. Changes to metadata immediately
affect diagnostics and compiler arguments. The hook's latest success or failure
is saved in `app/_build/native-plan.json`; it does not serialize the environment
provided by MoonBit. Reconfigure after changing planner sources, moving the
copy, changing toolchains or running `moon clean` (which removes local setup).
Invalid configuration arguments leave the previous setup intact; once planner
bootstrap begins, a failed bootstrap invalidates the previous setup.

Only `-I`, `-D`, `-U`, `-L` and `-l` are accepted by this adapter. Ordered link
arguments are kept together, with explicit Windows library filename mappings.
Unknown options are rejected with their metadata origin. Metadata is passed as
arguments, never evaluated by a shell. Use trusted metadata and build tools.
Options such as `-pthread`, `-Wl,...`, frameworks and `-isystem` need a deliberate
adapter extension; this example does not silently forward them.

The hook currently plans **all configured bindings** on each invocation. Both
libraries must therefore be installed even for the zlib-only command. Linking
is narrower: only imported packages propagate their libraries to a consumer.
This is an experimental native integration example, not a general manifest
rewriter, package manager or cross-compilation tool.
