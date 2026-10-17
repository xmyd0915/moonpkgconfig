"""Replay dependency failures and build an unmodified 0.3.0 template outside the checkout."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import xml.parsers.expat as reference

from native_ffi import ROOT


def xml_reference(case):
    parser = reference.ParserCreate()
    counts = {"elements": 0, "attributes": 0, "text_bytes": 0}

    def start(name, attributes):
        counts["elements"] += 1
        counts["attributes"] += len(attributes)

    def text(value):
        counts["text_bytes"] += len(value.encode("utf-8"))

    parser.StartElementHandler, parser.CharacterDataHandler = start, text
    data, chunk, status = bytes(case["input"]), case["chunk_size"], 1
    try:
        if not data:
            parser.Parse(b"", True)
        for offset in range(0, len(data), chunk):
            parser.Parse(data[offset:offset + chunk], offset + chunk >= len(data))
    except reference.ExpatError:
        status = 0
    return dict(counts, status=status, error=parser.ErrorCode,
                line=parser.CurrentLineNumber, column=parser.CurrentColumnNumber)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", choices=("zlib", "expat"), required=True)
    parser.add_argument("--pc-dir", type=Path, required=True)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--cc")
    parser.add_argument("--msvc-lib", action="append", default=[])
    args = parser.parse_args()
    directory = args.pc_dir.resolve()
    installed_pc = directory / (args.library + ".pc")
    before = hashlib.sha256(installed_pc.read_bytes()).hexdigest()
    working = Path(tempfile.mkdtemp(prefix="native-consumer-"))
    consumer = working / "consumer"
    shutil.copytree(ROOT / "examples/native-consumer", consumer,
                    ignore=shutil.ignore_patterns("_build", ".mooncakes", "__pycache__"))
    source_files = ("build.py", "cmd/plan/main.mbt")
    hashes = {name: hashlib.sha256((consumer / name).read_bytes()).hexdigest() for name in source_files}
    application = consumer / "apps" / args.library
    metadata = application / "native-app.pc"
    original = metadata.read_text(encoding="utf-8")
    command = [sys.executable, str(consumer / "build.py"), "--config", str(application / "consumer.json"),
               "--moon", args.moon]
    if args.cc:
        command.extend(["--cc", args.cc])
    for mapping in args.msvc_lib:
        command.extend(["--msvc-lib", mapping])
    evidence = {"library": args.library, "consumer": str(consumer), "platform": sys.platform,
                "metadata": str(installed_pc), "metadata_sha256": before,
                "template_sha256": hashes, "cases": [], "passed": False}

    def execute(label, options, status):
        earlier = set(consumer.glob("_build/consumer-*/evidence.json"))
        print(f"\n{args.library}: {label}", flush=True)
        invocation = subprocess.run([*command, *options], cwd=consumer, text=True,
                                    encoding="utf-8", capture_output=True)
        print(invocation.stdout + invocation.stderr, flush=True)
        if invocation.returncode != status:
            raise RuntimeError(f"Expected exit {status}, got {invocation.returncode}")
        reports = set(consumer.glob("_build/consumer-*/evidence.json")) - earlier
        if len(reports) != 1:
            raise RuntimeError("Expected one report for each template invocation")
        result = json.loads(reports.pop().read_text(encoding="utf-8"))
        if result["dependency"] != "xmyd0915/moonpkgconfig@0.3.0":
            raise RuntimeError("Expected the published 0.3.0 dependency")
        evidence["cases"].append({"case": label, "exit": status, **result})
        return result

    try:
        for label, text, paths, code in (
            ("missing dependency", original, [], "PC015"),
            ("version requirement", original.rsplit(">=", 1)[0] + ">= 999.0\n", ["--pc-dir", str(directory)], "PC016"),
        ):
            metadata.write_text(text, encoding="utf-8")
            result = execute(label, ["--plan-only", *paths], 1)
            for section in ("cflags", "libs"):
                problems = result["plan"][section]["diagnostics"]
                if len(problems) != 1 or problems[0]["code"] != code or problems[0]["location"] != {
                    "source": str(metadata), "line": 4, "column": 1,
                } or result["built"]:
                    raise RuntimeError(f"Wrong failure location or unexpected build: {result}")
        metadata.write_text(original, encoding="utf-8")
        result = execute("repaired build and run", ["--pc-dir", str(directory), "--run"], 0)
        if not result["built"] or any(result["plan"][key]["diagnostics"] for key in ("cflags", "libs")):
            raise RuntimeError("Repaired metadata did not produce a clean build")
        dependency = next(item for item in result["plan"]["dependencies"] if item["package"] == args.library)
        if dependency["path"] != ["native-app", args.library]:
            raise RuntimeError("Generic planner lost the private dependency route")
        for key in ("cflags", "libs"):
            flags = result["plan"][key]["flags"]
            if not flags or any(Path(flag["location"]["source"]) != installed_pc or flag["package"] != args.library for flag in flags):
                raise RuntimeError("Build flags lost the actual upstream installation source")
        if args.library == "zlib":
            if result["output"] != "MoonBit zlib FFI: CRC-32, 3 round trips and 3 error cases passed":
                raise RuntimeError("zlib application did not complete its checks")
        else:
            output = json.loads(result["output"])
            if len(output["cases"]) != 13 or output["boundary_checks"] != 4:
                raise RuntimeError("Expat application did not complete its checks")
            for case in output["cases"]:
                expected = xml_reference(case)
                if {key: case[key] for key in expected} != expected:
                    raise RuntimeError("XML output differs from the independent Python installation")
            private = [flag["value"] for flag in result["plan"]["cflags"]["flags"] if flag["field"] == "Cflags.private"]
            if private != ["-DXML_STATIC"]:
                raise RuntimeError("Generic build lost Expat's required private compiler definition")
            evidence["xml_reference"] = reference.EXPAT_VERSION
        if os.name == "nt":
            metadata.write_text(original + "Cflags: -funsupported-template-option\n", encoding="utf-8")
            failure = subprocess.run([*command, "--pc-dir", str(directory)], cwd=consumer,
                                     text=True, encoding="utf-8", capture_output=True)
            if failure.returncode != 1 or "Unsupported MSVC option '-funsupported-template-option' from native-app:Cflags" not in failure.stdout + failure.stderr:
                raise RuntimeError("Template accepted an unknown MSVC option or failed for another reason")
            evidence["unknown_msvc_option_rejected"] = True
            metadata.write_text(original, encoding="utf-8")
        if any(hashlib.sha256((consumer / name).read_bytes()).hexdigest() != value for name, value in hashes.items()):
            raise RuntimeError("Planner or build adapter changed between applications")
        if hashlib.sha256(installed_pc.read_bytes()).hexdigest() != before:
            raise RuntimeError("The installed upstream metadata changed")
        evidence["passed"] = True
    finally:
        destination = ROOT / "_build/verification" / ("native-consumer-" + args.library + ".json")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Published 0.3.0 generic template ({args.library}): failures, repair and native execution passed; {destination}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, StopIteration) as error:
        raise SystemExit(str(error))
