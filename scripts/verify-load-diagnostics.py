"""Exercise excluded dependency diagnostics through the native filesystem CLIs."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from native_ffi import ROOT


def run(command, status=0, diagnostics=False):
    result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                            capture_output=True, timeout=30)
    if result.returncode != status:
        raise AssertionError(f"Expected exit {status}: {command}\n{result.stdout}{result.stderr}")
    if diagnostics and result.stdout:
        raise AssertionError(f"Text failure wrote to stdout: {command}\n{result.stdout}")
    return (result.stderr if diagnostics else result.stdout).strip()


def build(moon, name, target):
    run([moon, "build", "--target", "native", "--release", "--target-dir", str(target), "cmd/" + name])
    directory = target / "native/release/build"
    candidates = [path for filename in (name + ".exe", name) for path in directory.rglob(filename)
                  if path.is_file() and path.parent.name == name and path.parent.parent.name == "cmd"]
    if len(candidates) != 1:
        raise AssertionError(f"Expected one {name} executable in {directory}, found {candidates}")
    return str(candidates[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--target-dir", type=Path, default=ROOT / "_build/diagnostic-cli")
    parser.add_argument("--report", type=Path, default=ROOT / "_build/verification/load-diagnostics.json")
    args = parser.parse_args()
    moon = shutil.which(args.moon)
    if not moon:
        raise RuntimeError("MoonBit CLI must be installed")
    target = args.target_dir.resolve()
    query, check = build(moon, "query", target), build(moon, "check", target)
    temporary = ROOT / ".tmp"
    temporary.mkdir(exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix="load-diagnostics-", dir=temporary))
    first, second = workspace / "first", workspace / "second"
    first.mkdir()
    second.mkdir()
    report = {"inputs": str(workspace), "cases": [], "skipped": [], "passed": False}

    def pc(directory, name, fields="", prefix="", metadata=True):
        text = prefix + (f"Name: {name}\nDescription: dependency fixture\nVersion: 1\n" if metadata else "") + fields
        path = directory / (name + ".pc")
        path.write_bytes(text.encode("utf-8"))
        return path

    def ask(label, name="app", options=("--libs",), directories=(first,), code=None,
            source=None, line=None, column=None, values=None):
        command = [query, str(directories[0]), name, *options, "--json"]
        for path in directories[1:]:
            command.extend(["--path", str(path)])
        data = json.loads(run(command, 1 if code else 0))
        if (not {"flags", "diagnostics"}.issubset(data)
                or data.get("schema_version") != 1 or data.get("command") != "query"
                or data.get("status") != ("diagnostics" if code else "ok")
                or data.get("error") is not None):
            raise AssertionError(f"Result schema changed: {data}")
        problems = data["diagnostics"]
        if [item["code"] for item in problems] != ([code] if code else []):
            raise AssertionError(f"{label}: {problems}")
        if source is not None and Path(problems[0]["location"]["source"]) != source:
            raise AssertionError(f"{label}: wrong file: {problems}")
        for key, expected in (("line", line), ("column", column)):
            if expected is not None and problems[0]["location"][key] != expected:
                raise AssertionError(f"{label}: wrong {key}: {problems}")
        if values is not None and [item["value"] for item in data["flags"]] != values:
            raise AssertionError(f"{label}: wrong arguments: {data}")
        report["cases"].append({"case": label, "result": data})
        return data

    try:
        app = pc(first, "app", "Requires: helper\nLibs: -lapp\nCflags: -I/app\n")
        helper = pc(first, "helper", prefix="prefix=${missing}\n")
        for mode in ("--libs", "--cflags", "--libs-only-l"):
            ask("malformed dependency " + mode, options=(mode,), code="PC004",
                source=helper, line=1, column=8)
        ask("malformed root", name="helper", code="PC004", source=helper, line=1, column=8)
        for mode in ("--exists", "--modversion", "--variable=prefix"):
            text = run([query, str(first), "app", mode], 1, diagnostics=True)
            if "PC004" not in text or "PC015" in text or str(helper) not in text:
                raise AssertionError(f"Metadata mode lost original diagnostics: {text}")
            report["cases"].append({"case": mode, "text": text})
        text = run([query, str(first), "app", "--cflags", "--explain"], 1, diagnostics=True)
        if "PC004" not in text or "PC015" in text:
            raise AssertionError("Explanation lost the original diagnostic")
        report["cases"].append({"case": "explain", "text": text})
        text = run([check, str(first)], 1, diagnostics=True)
        if text.count("PC004") != 1 or "PC015" in text or "1 diagnostics." not in text:
            raise AssertionError(f"Directory check duplicated or replaced errors: {text}")
        report["cases"].append({"case": "directory check", "text": text})

        pc(second, "helper", "Libs: -lhelper\n")
        ask("first broken file wins", directories=(first, second), code="PC004", source=helper)
        ask("reversed directory order", directories=(second, first), values=["-lapp", "-lhelper"])
        pc(first, "provider", "Provides: helper = 2\nLibs: -lprovider\n")
        ask("excluded exact id blocks provider", code="PC004", source=helper)
        helper.unlink()
        ask("provider without exact file", values=["-lapp", "-lprovider"])
        (first / "provider.pc").unlink()
        ask("truly absent dependency", code="PC015", source=app, line=4, column=1)

        pc(first, "app", "Requires: middle\nLibs: -lapp\n")
        pc(first, "middle", "Requires: helper\n")
        pc(first, "helper", "Description: no name\nVersion: 1\n", metadata=False)
        ask("transitive invalid metadata", code="PC010", source=helper, line=1, column=1)
        pc(first, "app", "Requires: left right\n")
        pc(first, "left", "Requires: helper\n")
        pc(first, "right", "Requires: helper\n")
        ask("shared invalid dependency", code="PC010", source=helper)

        pc(first, "helper", prefix="prefix=${missing}\n")
        pc(first, "app", "Requires.private: helper\nLibs: -lapp\n")
        ask("dynamic libs ignore private failure", values=["-lapp"])
        ask("static libs include private failure", options=("--libs", "--static"), code="PC004", source=helper)
        ask("cflags include private failure", options=("--cflags",), code="PC004", source=helper)
        pc(first, "app", "Requires: middle >= 2\n")
        ask("version failure excludes unreachable child", code="PC016", source=app)
        pc(first, "good", "Libs: -lgood\n")
        ask("unrelated invalid files", name="good", values=["-lgood"])

        pc(first, "app", "Requires: helper\nLibs: -lapp\n")
        pc(first, "helper", "Libs: -lhelper\n")
        ask("repair and reload", values=["-lapp", "-lhelper"])

        entries = workspace / "entries with spaces"
        fallback = workspace / "fallback with spaces"
        entries.mkdir()
        fallback.mkdir()
        pc(entries, "good", "Libs: -lgood\n")
        bad = entries / "bad.pc"
        pc(fallback, "bad", "Libs: -lbad\n")

        def check_entries(label, directories, expected_codes, package_ids):
            command = [check, str(directories[0]), "--json"]
            for directory in directories[1:]:
                command.extend(["--path", str(directory)])
            data = json.loads(run(command, 1 if expected_codes else 0))
            if (data["status"] != ("diagnostics" if expected_codes else "ok")
                    or data["error"] is not None
                    or [item["code"] for item in data["diagnostics"]] != expected_codes
                    or data["package_ids"] != package_ids
                    or data["package_count"] != len(package_ids)
                    or data["file_count"] != sum(len(list(path.glob("*.pc"))) for path in directories)):
                raise AssertionError(f"{label}: {data}")
            report["cases"].append({"case": label, "result": data})
            return data

        def broken_entry(label, code, reason):
            ask(label + " does not poison unrelated query", name="good", directories=(entries,), values=["-lgood"])
            for directories, suffix in (((entries,), " root"), ((entries, fallback), " wins over fallback")):
                data = ask(label + suffix, name="bad", directories=directories,
                           code=code, source=bad, line=1, column=1)
                message = data["diagnostics"][0]["message"]
                if str(bad) not in message or reason not in message:
                    raise AssertionError(f"{label}: missing path or cause: {message}")
            check_entries(label + " is a directory diagnostic", (entries,), [code], ["good"])
            check_entries(label + " repeated directory deduplicates diagnostic", (entries, entries), [code], ["good"])
            ask(label + " reversed priority selects valid file", name="bad",
                directories=(fallback, entries), values=["-lbad"])
            pc(entries, "left", "Requires: bad\n")
            pc(entries, "right", "Requires: bad\n")
            pc(entries, "app", "Requires: left right\n")
            ask(label + " shared dependency keeps original error", directories=(entries,),
                code=code, source=bad, line=1, column=1)
            pc(entries, "provider", "Provides: bad = 1\nLibs: -lprovider\n")
            ask(label + " exact file blocks virtual fallback", name="bad", directories=(entries,),
                code=code, source=bad)
            for name in ("left", "right", "app", "provider"):
                (entries / (name + ".pc")).unlink()

        bad.mkdir()
        broken_entry("directory named pc", "PC019", "Not a regular file")
        bad.rmdir()

        bad.write_bytes(b"Name: bad\nDescription: caf\xe9\nVersion: 1\nLibs: -lbad\n")
        broken_entry("invalid UTF-8", "PC020", "not valid UTF-8")
        for label, raw in (("truncated sequence", b"\xe2\x82"), ("overlong sequence", b"\xc0\xaf"),
                           ("surrogate sequence", b"\xed\xa0\x80"), ("out of range sequence", b"\xf4\x90\x80\x80")):
            bad.write_bytes(b"Name: bad\nDescription: " + raw + b"\nVersion: 1\n")
            ask(label, name="bad", directories=(entries,), code="PC020", source=bad)
        bad.unlink()

        try:
            bad.symlink_to(entries / "missing-target.pc")
        except OSError as error:
            if os.name != "nt" or getattr(error, "winerror", None) not in (5, 50, 1314):
                raise
            report["skipped"].append({"case": "dangling symbolic link", "reason": f"OS cannot create symlink: winerror {error.winerror}"})
        else:
            try:
                broken_entry("dangling symbolic link", "PC019", "Could not read metadata file")
            finally:
                bad.unlink()

        if os.name != "nt":
            pc(entries, "bad", "Libs: -lbad\n")
            bad.chmod(0)
            try:
                if os.access(bad, os.R_OK):
                    report["skipped"].append({"case": "unreadable file", "reason": "Process can read mode-000 files"})
                else:
                    broken_entry("unreadable file", "PC019", "Could not read metadata file")
            finally:
                bad.chmod(0o600)
                bad.unlink()

        pc(entries, "bad", "Libs: -lrepaired\n", prefix="label=\u4fee\u590d\n")
        ask("repair unreadable entry and reload UTF-8", name="bad", directories=(entries,), values=["-lrepaired"])
        check_entries("repaired entries are valid", (entries,), [], ["bad", "good"])
        pc(entries, "builtin", "Cflags: -I${pc_sysrootdir}/include\n")
        ask("default sysroot expansion input", name="builtin", directories=(entries,), options=("--cflags",), values=["-I/include"])
        ask("explicit sysroot expansion input", name="builtin", directories=(entries,),
            options=("--cflags", "--define-variable=pc_sysrootdir=/sdk"), values=["-I/sdk/include"])

        missing = workspace / "missing search directory"
        not_directory = pc(workspace, "not-a-directory")

        def directory_failure(path):
            context = f"Could not read search directory {path}:"
            for executable, arguments, command_name in ((query, [str(entries), "good", "--libs"], "query"),
                                                        (check, [str(entries)], "check")):
                arguments += ["--path", str(path)]
                data = json.loads(run([executable, *arguments, "--json"], 2))
                if (data["status"] != "io_error" or data["error"]["kind"] != "io"
                        or context not in data["error"]["message"] or data["diagnostics"]
                        or data["error"]["message"].endswith((": No error", ": Success"))):
                    raise AssertionError(f"Directory failure lost context: {data}")
                if command_name == "check" and (data["file_count"] is not None or data["package_count"] is not None):
                    raise AssertionError(f"Directory failure reported partial counts: {data}")
                text = run([executable, *arguments], 2, diagnostics=True)
                if context not in text:
                    raise AssertionError(f"Text directory error omitted failing path: {text}")
                report["cases"].append({"case": f"{command_name} fails at actual search path {path.name}", "result": data})

        for path in (missing, not_directory):
            directory_failure(path)
        if os.name != "nt":
            inaccessible = workspace / "inaccessible search directory"
            inaccessible.mkdir()
            inaccessible.chmod(0)
            try:
                if os.access(inaccessible, os.R_OK):
                    report["skipped"].append({"case": "inaccessible directory", "reason": "Process can list mode-000 directories"})
                else:
                    directory_failure(inaccessible)
            finally:
                inaccessible.chmod(0o700)
        report["passed"] = True
    finally:
        output = args.report.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Filesystem dependency diagnostics: {len(report['cases'])} cases passed; {output}")


if __name__ == "__main__":
    main()
