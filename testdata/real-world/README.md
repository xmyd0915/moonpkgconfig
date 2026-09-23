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
