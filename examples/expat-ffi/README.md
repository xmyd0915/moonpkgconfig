# Expat static XML consumer

This native MoonBit example reads the compiler and linker arguments from an
actual Expat installation. Static compilation selects the installed
`Cflags.private: -DXML_STATIC` field; the C wrapper never defines that macro
itself. Metadata remains unchanged throughout verification.

## Build and verify

Requirements: the repository's pinned MoonBit toolchain, Python 3.9+, CMake,
and a native C compiler. Windows requires x64 Visual Studio C++ tools and the
Windows SDK. Environment discovery affects only the verification process and
its children.

From the repository root:

```sh
python scripts/verify-expat.py
python scripts/verify-expat.py --cmake /path/to/cmake --archive /path/to/expat-2.6.2.tar.gz
```

The script downloads the official Expat 2.6.2 source archive and checks SHA-256
`d4cf38d26e21a56654ffe4acd9cd5481164619626802328506a2869afab29ab3`.
Source: <https://github.com/libexpat/libexpat/releases/tag/R_2_6_2>.
This fixed version is a regression fixture matching the upstream template in
the compatibility corpus. The integration does not choose a production
dependency version for consumers.

It builds and installs the narrow-character static library with CMake,
disabling tests, tools and examples. Windows uses the static MSVC runtime and
installs `libexpatMT.lib`; POSIX installs `libexpat.a`. It then queries the
unmodified installed `expat.pc` and generates a temporary MoonBit native
configuration using the returned argument arrays. No hand-written
`-DXML_STATIC` is added to the build.

For an existing compatible installation:

```sh
python scripts/verify-expat-ffi.py --pc-dir /path/to/installation/lib/pkgconfig
```

The example is an independent module; the root library does not depend on
Expat. CMake and MoonBit outputs remain in ignored `.tmp` directories.

## What is checked

- Three XML documents are parsed with chunk sizes 1, 7 and 4096: nine parses,
  including attributes, entity replacement and UTF-8 sequences split across
  input chunks.
- Four malformed inputs exercise empty/incomplete documents, a mismatched
  closing tag and invalid UTF-8.
- Four wrapper checks reject negative/oversized input lengths, a zero chunk
  size and a short summary buffer. Input is bounded to 1 MiB in this example.
- Python's separately installed `xml.parsers.expat` verifies element counts,
  attribute counts, text byte counts, parse status, error code, line and
  zero-based column. Its actual Expat version is recorded in the report.
- On MSVC, removing only the queried private compiler field must reproduce an
  unresolved `__imp_XML_*` link error. The successful build uses the same
  static library and restores that field. POSIX does not use this DLL-import
  convention, so the negative control is explicitly marked not applicable.

The report is `_build/verification/expat.json`; Windows additionally retains
`expat-negative-link.log`. The source archive hash, static library hash,
metadata hash, full parameter origins and per-input parse results are saved.
CI uploads `ubuntu-expat` and `windows-expat` artifacts. This verifies the
selected build configuration and fixtures, rather than all Expat features.
