# Real-world upstream templates

This directory contains two unmodified pkg-config template contents from
tagged upstream releases. Only the filename suffix changed from `.pc.in` to
`.pc` so the directory loader can exercise them directly.

| Local file | Project and release | Fixed commit | Upstream path | License |
| --- | --- | --- | --- | --- |
| `zlib.pc` | zlib 1.3.1 | `51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf` | `zlib.pc.in` | zlib License (`LICENSE.zlib`) |
| `libffi.pc` | libffi 3.4.6 | `3d0ce1e6fcf19f853894862abcbac0ae78a7be60` | `libffi.pc.in` | MIT (`LICENSE.libffi`) |

Upstream repositories:

- <https://github.com/madler/zlib>
- <https://github.com/libffi/libffi>

The `@...@` values are build-system substitution markers present in the
original templates. Keeping them unchanged tests parsing and query behavior
without pretending these templates describe locally installed libraries.

The `templates/` subdirectory adds four byte-for-byte upstream inputs:

| File | Release | Fixed commit | Upstream path | License file |
| --- | --- | --- | --- | --- |
| `libuv.pc.in` | libuv 1.48.0 | `e9f29cb984231524e3931aa0ae2c5dae1a32884e` | `libuv.pc.in` | `LICENSE.libuv` (MIT and bundled notices) |
| `libpng.pc.in` | libpng 1.6.59 | `cd952f49f95bb27154ae77dbb103032d95f6e580` | `libpng.pc.in` | `LICENSE.libpng` (libpng License) |
| `libpcre2-8.pc.in` | PCRE2 10.44 | `6ae58beca071f13ccfed31d03b3f479ab520639b` | `libpcre2-8.pc.in` | `LICENSE.pcre2` (upstream `LICENCE`, BSD terms) |
| `expat.pc.in` | Expat 2.6.2 | `fa75b96546c069d17b8f80d91e0f4ef0cde3790d` | `expat/expat.pc.in` | `LICENSE.expat` (MIT) |

`corpus.json` records repositories, original paths, commits, SHA-256 hashes of
all six templates and their licenses, explicit substitution values, and
independently specified expected flags. Source URLs are obtained as
`https://github.com/<repository>/blob/<commit>/<upstream>`.

`python scripts/verify-compatibility.py` verifies those bytes and creates
configured copies in the ignored `.tmp/compatibility-*` directory. It compares
120 queries with declared expectations and pkgconf 3.0.7, including libpng's
private zlib dependency and Expat's static-only `-DXML_STATIC` compiler flag.
The selected prefix, platform libraries and static build definitions are test
configurations, not claims about installed libraries or every upstream build
configuration. These templates are never executed or passed to a compiler.

The same check includes four original cross-package static flag ordering cases
and seeded argument/malformed-input checks. Scope and reproduction are
documented in [the compatibility report](../../docs/compatibility.md).
