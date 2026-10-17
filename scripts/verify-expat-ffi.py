"""Query real Expat metadata, build a MoonBit XML consumer and verify its output."""

import hashlib
import json
import os
from pathlib import Path
import sys
import xml.parsers.expat as reference

from native_ffi import ROOT, arguments, build_example, query, values


def reference_parse(case):
    data = bytes(case["input"])
    parser = reference.ParserCreate()
    counts = {"elements": 0, "attributes": 0, "text_bytes": 0}

    def start(name, attributes):
        counts["elements"] += 1
        counts["attributes"] += len(attributes)

    def text(value):
        counts["text_bytes"] += len(value.encode("utf-8"))

    parser.StartElementHandler = start
    parser.CharacterDataHandler = text
    status = 1
    try:
        if not data:
            parser.Parse(b"", True)
        chunk = case["chunk_size"]
        for offset in range(0, len(data), chunk):
            parser.Parse(data[offset:offset + chunk], offset + chunk >= len(data))
    except reference.ExpatError:
        status = 0
    return dict(counts, status=status, error=parser.ErrorCode,
                line=parser.CurrentLineNumber, column=parser.CurrentColumnNumber)


def main():
    moon, compiler, directories, mappings = arguments(__doc__, allow_windows=True)
    pc = directories[0] / "expat.pc"
    if not pc.is_file():
        raise RuntimeError(f"no installed expat.pc in {directories[0]}")
    version = query(moon, directories, "expat", "--modversion")
    dynamic = query(moon, directories, "expat", "--cflags")
    static = query(moon, directories, "expat", "--cflags", static=True)
    libs = query(moon, directories, "expat", "--libs", static=True)
    private = [flag for flag in static if flag["field"] == "Cflags.private"]
    if "-DXML_STATIC" in values(dynamic) or values(private) != ["-DXML_STATIC"]:
        raise RuntimeError("Expat's static-only compiler definition was not selected correctly")
    if Path(private[0]["location"]["source"]) != pc:
        raise RuntimeError("Static compiler flag lost its actual installation source")
    metadata_hash = hashlib.sha256(pc.read_bytes()).hexdigest()
    options = {"msvc_libs": mappings, "imports": ("moonbitlang/core/encoding/utf8",)}
    output = build_example(moon, compiler, "expat-ffi", "expat_stub.c", static, libs, None, **options)
    result = json.loads(output)
    if len(result["cases"]) != 13 or result["boundary_checks"] != 4:
        raise RuntimeError("XML consumer did not run all expected cases")
    for case in result["cases"]:
        expected = reference_parse(case)
        actual = {key: case[key] for key in expected}
        if actual != expected:
            raise RuntimeError(f"XML parse differs from independent Python installation: {actual} != {expected}")
    negative = {"status": "not_applicable", "reason": "DLL import definitions are specific to MSVC"}
    if os.name == "nt":
        # Removing only the real private field must reproduce the import-symbol
        # link failure, rather than an unrelated compiler or configuration error.
        try:
            build_example(moon, compiler, "expat-ffi", "expat_stub.c", dynamic, libs, None, **options)
        except RuntimeError as error:
            if "__imp_XML_" not in str(error):
                raise RuntimeError("Negative control failed for an unrelated reason") from error
            log = ROOT / "_build/verification/expat-negative-link.log"
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text(str(error), encoding="utf-8")
            negative = {"status": "expected_link_failure", "symbols": "__imp_XML_*", "log": str(log)}
        else:
            raise RuntimeError("MSVC linked the static Expat library without its required private definition")
    if hashlib.sha256(pc.read_bytes()).hexdigest() != metadata_hash:
        raise RuntimeError("The upstream installed metadata was modified")
    report = {"schema": 1, "version": version, "platform": sys.platform,
              "reference": reference.EXPAT_VERSION, "metadata": str(pc), "metadata_sha256": metadata_hash,
              "dynamic_cflags": dynamic, "static_cflags": static, "static_libs": libs,
              "negative_control": negative, **result, "passed": True}
    destination = ROOT / "_build/verification/expat.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Expat {version}: 9 valid/chunked parses, 4 malformed inputs and 4 FFI bounds passed")
    print(f"Static compiler definition: {private[0]['value']} from {pc}:{private[0]['location']['line']}")
    print(f"Python XML reference: {reference.EXPAT_VERSION}; negative control: {negative['status']}")
    print(f"Expat evidence: {destination}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
