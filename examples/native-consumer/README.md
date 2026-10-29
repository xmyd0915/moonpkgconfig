# Published 0.3.1 native consumer template

Copy this entire directory outside the checkout to use MoonCakes
`xmyd0915/moonpkgconfig@0.3.1`. The MoonBit planner loads explicit `.pc`
directories and returns compiler/linker arguments, source locations, versions
and dependency routes. The Python adapter turns that data into a native
`moon.pkg` for a copy of your application. It uses only the standard library.

The same planner and adapter build three included applications:

| Application | What it does |
| --- | --- |
| `apps/zlib` | Checks CRC-32, three compression round trips and three error cases |
| `apps/expat` | Parses XML in chunks and checks malformed inputs and FFI buffer bounds |
| `apps/zlib-files` | Compresses and decompresses actual files with the zlib stream format |

These applications are maintained in this repository. They demonstrate how to
use the published library; they are not third-party adoption examples.

## Run

Prerequisites: MoonBit `0.10.16+b1a0e846e`, Python 3.9+, and an installed native
library with its `.pc` file. Linux needs a C compiler. Windows needs the x64
Visual Studio C++ tools and Windows SDK; MoonBit discovers MSVC. The adapter
selects `/MT`, matching the static fixtures used in this repository. Registry
access is needed on the first build. No local module override is used.

From your copy:

```sh
python build.py --config apps/zlib/consumer.json --pc-dir /path/to/zlib/lib/pkgconfig --run
python build.py --config apps/expat/consumer.json --pc-dir /path/to/expat/lib/pkgconfig --run
python build.py --config apps/zlib-files/consumer.json --pc-dir /path/to/zlib/lib/pkgconfig
```

For a Windows CMake zlib installation:

```powershell
python build.py --config apps/zlib/consumer.json --pc-dir C:/native/zlib/share/pkgconfig --msvc-lib z=zlibstatic.lib --run
python build.py --config apps/expat/consumer.json --pc-dir C:/native/expat/lib/pkgconfig --run
python build.py --config apps/zlib-files/consumer.json --pc-dir C:/native/zlib/share/pkgconfig --msvc-lib z=zlibstatic.lib
```

Repeat `--pc-dir` for additional search directories, in priority order. The
application's directory is searched first. Paths containing spaces must be
quoted in the command and in the original `.pc` flag fields. Installed metadata
is read without changing it. `--plan-only` prints arguments and saves the plan
without building the application. Omit `--run` to build without executing it.
Every completed plan saves `_build/consumer-*/evidence.json`, including failed
dependency plans. A successful build adds an absolute `executable` path to the
report and prints it. Exit codes are 0 for success, 1 for a diagnostic/build
error, and 2 for invalid arguments.

To prepare fixed static zlib and Expat installations and verify all three
applications from the repository root, use `python scripts/review-native.py`.
This route also requires CMake 3.15+ and `make` on Linux, or MSVC on Windows.
See the repository's [native walkthrough](../../docs/native-walkthrough.md)
for preparation options and report details. The copied template itself only
needs the installed dependencies and the tools listed above.

## Use the file tool

Build `apps/zlib-files` without `--run`, then use the printed executable path.
For example, in PowerShell, set `$tool` to that path:

```powershell
$tool = 'C:/path/printed/by/build/compressor.exe'
& $tool compress input.bin output.zlib
& $tool decompress output.zlib restored.bin
```

On Linux:

```sh
"/path/printed/by/build/compressor" compress input.bin output.zlib
"/path/printed/by/build/compressor" decompress output.zlib restored.bin
```

The application processes one complete file in memory. Compression accepts at
most 64 MiB of input, and decompression produces at most 64 MiB. Compressed input
is also size-limited to zlib's compression bound for 64 MiB. The format is a
zlib stream, not a ZIP archive or gzip file. The reader enforces the input limit
while reading, and output files are created exclusively so existing paths cannot
be overwritten. A failed write may leave a partial new file; the tool does not
delete paths on failure. Choose a new path for each run. Invalid streams and missing input files return
an error without creating output. Verification checks empty, UTF-8 text and
binary files, including both directions of interoperability with Python zlib.

## Adapt to your application

1. Copy an `apps` sample and replace its MoonBit code and C/C++ wrappers.
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
name. The adapter generates the copied root `moon.pkg`. The source application
may omit that file or include the template's imports, executable declaration and
native-stub list matching `consumer.json`. Custom `moon.pkg` settings and
`moon.pkg.json` are rejected before building, so they cannot be silently lost.
For multiple packages or an existing build configuration, use the planner's
JSON as input to your own adapter.

## Failure, location and repair

Run without `--pc-dir` to see `PC015` at the sample's dependency declaration on
line 4. Change its required version to `>= 999.0`, supply the installed
directory, and `PC016` identifies the same declaration. A dependency containing
`broken=${missing}` on its first line produces `PC004` at that file's line 1,
column 8. The 0.3.1 planner passes the loader's `diagnostics_by_package` map to
flag and dependency-path queries, preserving the original error location.

Restore the requirement and valid dependency metadata to build/run
successfully. Repository verification performs the failures and repair in
temporary copies outside the checkout. It checks the installed `.pc` files'
hashes, compares Expat output with Python's independent XML parser, and checks
that the same planner and adapter build all three applications. The file-tool
case removes a broken temporary override before reusing the real installation;
the original installed metadata is not edited.

On Windows, this small adapter understands `-I`, `-D`, `-U`, `-L` and `-l`,
including split operands from the same source. Library filename mappings are
explicit; unknown options and unsupported library names fail with their origin.
POSIX builds preserve the original argument arrays. Metadata is passed to the
compiler as arguments, without evaluation by a shell. Use trusted metadata and
compatible compiler, library and runtime configurations.

MIT license; see [LICENSE](LICENSE).
