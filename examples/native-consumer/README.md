# Published 0.3.0 native consumer template

Copy this entire directory outside the checkout to use MoonCakes
`xmyd0915/moonpkgconfig@0.3.0`. The MoonBit planner loads explicit `.pc`
directories and returns compiler/linker arguments, source locations, versions
and dependency routes. The Python adapter turns that data into a native
`moon.pkg` for a copy of your application. It uses only the standard library.

The same planner and adapter build both included applications. The zlib sample
checks CRC-32, three compression round trips and three error cases. The Expat
sample parses XML in chunks and checks malformed inputs and FFI buffer bounds.
The C wrappers and MoonBit checks match the separately maintained FFI examples.

## Run

Prerequisites: MoonBit `0.10.14+7d59c7ec9`, Python 3.9+, and an installed native
library with its `.pc` file. Linux needs a C compiler. Windows needs the x64
Visual Studio C++ tools and Windows SDK; MoonBit discovers MSVC. The adapter
selects `/MT`, matching the static fixtures used in this repository. Registry
access is needed on the first build. No local module override is used.

From your copy:

```sh
python build.py --config apps/zlib/consumer.json --pc-dir /path/to/zlib/lib/pkgconfig --run
python build.py --config apps/expat/consumer.json --pc-dir /path/to/expat/lib/pkgconfig --run
```

For the repository's Windows CMake zlib installation:

```powershell
python build.py --config apps/zlib/consumer.json --pc-dir C:/native/zlib/share/pkgconfig --msvc-lib z=zlibstatic.lib --run
python build.py --config apps/expat/consumer.json --pc-dir C:/native/expat/lib/pkgconfig --run
```

Repeat `--pc-dir` for additional search directories, in priority order. The
application's directory is searched first. Paths containing spaces must be
quoted in the command and in the original `.pc` flag fields. Installed metadata
is read without changing it. `--plan-only` prints arguments and saves the plan
without building the application. Omit `--run` to build without executing it.
Every invocation saves `_build/consumer-*/evidence.json`, including failed
dependency plans. Exit codes are 0 for success, 1 for a diagnostic/build error,
and 2 for invalid arguments.

## Adapt to your application

1. Copy either `apps` sample and replace its MoonBit code and C/C++ wrappers.
   This template supports one executable root package with native stubs.
2. Set `consumer.json`: `package` selects the root `.pc` identifier, `static`
   selects static compiler/linker queries, `stubs` lists C/C++ filenames, and
   `imports` lists MoonBit package imports. Keep MoonBit module dependencies in
   the application's `moon.mod`.
3. Update the application's `.pc` file with the dependencies and version
   requirements you need. Its filename must match `package`.
4. Pass the installed dependency directories and build. Inspect each flag's
   file/line and the JSON dependency routes when troubleshooting.

Neither `cmd/plan/main.mbt` nor `build.py` contains a library-specific package
name. The adapter generates the copied root `moon.pkg`; it does not preserve
an application's existing custom build options or handle multiple packages.
For a larger build system, use the planner's JSON as input to your own adapter.

## Failure, location and repair

Run without `--pc-dir` to see `PC015` at the sample's dependency declaration on
line 4. Change its required version to `>= 999.0`, supply the installed
directory, and `PC016` identifies the same declaration. Restore the requirement
and directory to build/run successfully. Repository verification performs both
failures, repair and real execution in a fresh copy outside the checkout; Expat
output is also compared with Python's independent XML parser.

The planner deliberately uses the published 0.3.0 interface. That version may
report a malformed transitive dependency as missing. Version 0.3.1 adds an
`unavailable` diagnostic map for that case; it is not part of 0.3.0.

On Windows, this small adapter understands `-I`, `-D`, `-U`, `-L` and `-l`,
including split operands from the same source. Library filename mappings are
explicit; unknown options and unsupported library names fail with their origin.
POSIX builds preserve the original argument arrays. Metadata is passed to the
compiler as arguments, without evaluation by a shell. Use trusted metadata and
compatible compiler, library and runtime configurations.

MIT license; see [LICENSE](LICENSE).
