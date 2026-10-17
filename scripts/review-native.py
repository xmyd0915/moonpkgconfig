"""Show a damaged dependency, repair it, then build two published-package consumers."""

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

from native_ffi import ROOT, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zlib-pc-dir", type=Path, required=True)
    parser.add_argument("--expat-pc-dir", type=Path, required=True)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--cc")
    parser.add_argument("--zlib-msvc-lib", action="append", default=[])
    args = parser.parse_args()
    temporary = ROOT / ".tmp"
    temporary.mkdir(exist_ok=True)
    working = Path(tempfile.mkdtemp(prefix="native-walkthrough-", dir=temporary))
    application = working / "application"
    dependency = working / "dependency"
    application.mkdir()
    dependency.mkdir()
    shutil.copyfile(ROOT / "examples/native-consumer/apps/expat/native-app.pc", application / "native-app.pc")
    installed = args.expat_pc_dir.resolve() / "expat.pc"
    original = installed.read_text(encoding="utf-8")
    damaged = dependency / "expat.pc"
    damaged.write_text("broken=${missing}\n" + original, encoding="utf-8")
    command = [args.moon, "run", "--target", "native", "cmd/query", str(application), "native-app",
               "--cflags", "--static", "--path", str(dependency), "--json"]
    print("1/4 Query a damaged dependency copy (unreleased checkout)", flush=True)
    failed = json.loads(run(command, ROOT, 1))
    if len(failed["diagnostics"]) != 1 or failed["diagnostics"][0]["code"] != "PC004":
        raise RuntimeError("Expected the original undefined-variable diagnostic")
    problem = failed["diagnostics"][0]
    at = problem["location"]
    if Path(at["source"]) != damaged or at["line"] != 1 or at["column"] != 8:
        raise RuntimeError("The damage was not located in the dependency file")
    print(f"{problem['code']} {at['source']}:{at['line']}:{at['column']} {problem['message']}", flush=True)
    print("2/4 Remove the invalid definition and query again", flush=True)
    damaged.write_text(original, encoding="utf-8")
    repaired = json.loads(run(command, ROOT))
    if repaired["diagnostics"] or "-DXML_STATIC" not in [flag["value"] for flag in repaired["flags"]]:
        raise RuntimeError("Repair did not restore Expat's static compiler flags")
    print("Repair succeeded; static compiler flags include -DXML_STATIC", flush=True)
    print("3/4 Build and run zlib with the published 0.3.0 template", flush=True)
    for library, directory in (("zlib", args.zlib_pc_dir), ("expat", args.expat_pc_dir)):
        if library == "expat":
            print("4/4 Change application configuration and build/run Expat with the same template", flush=True)
        consumer = [sys.executable, str(ROOT / "scripts/verify-native-consumer.py"),
                    "--library", library, "--pc-dir", str(directory.resolve()), "--moon", args.moon]
        if args.cc:
            consumer.extend(["--cc", args.cc])
        if library == "zlib":
            for mapping in args.zlib_msvc_lib:
                consumer.extend(["--msvc-lib", mapping])
        print(run(consumer, ROOT), flush=True)
    reports = [json.loads((ROOT / "_build/verification" / ("native-consumer-" + library + ".json")).read_text(encoding="utf-8"))
               for library in ("zlib", "expat")]
    if reports[0]["template_sha256"] != reports[1]["template_sha256"] or not all(report["passed"] for report in reports):
        raise RuntimeError("The two applications did not pass with identical template code")
    report = ROOT / "_build/verification/native-walkthrough.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps({"damaged": failed, "repaired": repaired, "inputs": str(working),
                                  "consumers": ["native-consumer-zlib.json", "native-consumer-expat.json"],
                                  "passed": True}, indent=2) + "\n", encoding="utf-8")
    print(f"Native walkthrough: passed; {report}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error))
