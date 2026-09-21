# pkgconf 3.0.7 compatibility fixtures

These ten `.pc` files are unmodified copies from the official pkgconf test
suite at tag `pkgconf-3.0.7`, commit
`0c9e506b64124d8727b68d8af0ed73739e66e2ba`:

<https://github.com/pkgconf/pkgconf/tree/0c9e506b64124d8727b68d8af0ed73739e66e2ba/tests>

| File in this directory | Upstream path |
| --- | --- |
| `perfect.pc` | `tests/lib-pccritic/perfect.pc` |
| `variable-whitespace.pc` | `tests/lib1/variable-whitespace.pc` |
| `multiline.pc` | `tests/lib1/multiline.pc` |
| `no-trailing-newline.pc` | `tests/lib1/no-trailing-newline.pc` |
| `escaped-backslash.pc` | `tests/lib1/escaped-backslash.pc` |
| `fragment-quoting.pc` | `tests/lib1/fragment-quoting.pc` |
| `dollar-sign-escape.pc` | `tests/lib1/dollar-sign-escape.pc` |
| `dos-lineendings.pc` | `tests/lib1/dos-lineendings.pc` |
| `flag-whitespace.pc` | `tests/lib1/flag-whitespace.pc` |
| `cflags-libs-only.pc` | `tests/lib1/cflags-libs-only.pc` |

The files exercise metadata, variable whitespace, logical-line folding, CRLF,
a missing final newline, escaped backslashes, quoted fragments, dollar-sign
escaping, and split `-I` arguments. `LICENSE.pkgconf` contains the upstream ISC
license notice.

Passing this selected corpus demonstrates compatibility with these inputs only.
It is not a claim that MoonPkgConfig passes the complete pkgconf test suite or
implements every pkgconf extension.
