#!/usr/bin/env python3
"""Boundary checks for the example adapter, independent of the host compiler."""

import argparse
import shlex
import unittest

from native_ffi import library_mapping, msvc_flags


COMPILE = {"-I": "/I", "-D": "/D", "-U": "/U"}
LINK = {"-L": "/LIBPATH:", "-l": ""}


def flags(*values):
    return [
        {"value": value, "package": "zlib", "field": "Cflags",
         "location": {"file": "zlib.pc", "line": 12, "column": 1}}
        for value in values
    ]


class MsvcAdapterTests(unittest.TestCase):
    def test_compile_operands_and_manifest_quoting(self):
        source = flags('-IC:/SDK with spaces/include', "-I", r"C:\SDK\include",
                       '-DTEXT="two words"', "-U", "OLD")
        expected = ['/IC:/SDK with spaces/include', r"/IC:\SDK\include",
                    '/DTEXT="two words"', "/UOLD"]
        actual = msvc_flags(source, COMPILE)
        self.assertEqual(actual, expected)
        self.assertEqual(shlex.split(shlex.join(actual)), expected)

    def test_link_order_and_explicit_mapping(self):
        source = flags("-LC:/SDK one/lib", "-l", "z", "-L", "C:/SDK two/lib", "-lother", "-lz")
        self.assertEqual(msvc_flags(source, LINK, {"z": "zlibstatic.lib"}), [
            "/LIBPATH:C:/SDK one/lib", "zlibstatic.lib", "/LIBPATH:C:/SDK two/lib",
            "other.lib", "zlibstatic.lib",
        ])

    def test_empty_flags(self):
        self.assertEqual(msvc_flags([], LINK), [])

    def test_unknown_options_are_rejected(self):
        for value in ("-pthread", "-Wl,--start-group", "@options.rsp", "/NODEFAULTLIB"):
            with self.subTest(value=value), self.assertRaisesRegex(RuntimeError, "unsupported MSVC"):
                msvc_flags(flags(value), LINK)

    def test_missing_operands_are_rejected(self):
        for source in (flags("-I"), flags("-I", "-DNAME"), flags("-I", "")):
            with self.assertRaisesRegex(RuntimeError, "missing operand"):
                msvc_flags(source, COMPILE)

    def test_operands_cannot_cross_origins(self):
        for key, value in (("package", "other"), ("field", "Libs"),
                           ("location", {"file": "zlib.pc", "line": 13, "column": 1})):
            source = flags("-I", "include")
            source[1][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(RuntimeError, "missing operand"):
                msvc_flags(source, COMPILE)

    def test_nonportable_library_spelling_is_rejected(self):
        for value in ("-l:archive.a", "-l../archive", "-l@response", "-l-option"):
            with self.subTest(value=value), self.assertRaisesRegex(RuntimeError, "unsupported MSVC library"):
                msvc_flags(flags(value), LINK)

    def test_mapping_requires_a_library_filename(self):
        self.assertEqual(library_mapping("z=zlibstatic.lib"), ("z", "zlibstatic.lib"))
        for value in ("z", "=z.lib", "z=../z.lib", "z=C:/z.lib", "z=z.a", "z=@args.lib", "z=-flag.lib"):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                library_mapping(value)


if __name__ == "__main__":
    unittest.main()
