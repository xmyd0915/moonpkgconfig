"""Exercise excluded dependency diagnostics through the native filesystem CLIs."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from native_ffi import ROOT


def run(command, status=0):
    result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                            capture_output=True, timeout=30)
    if result.returncode != status:
        raise AssertionError(f"Expected exit {status}: {command}\n{result.stdout}{result.stderr}")
    return result.stdout.strip()


def build(moon, name):
    run([moon, "build", "--target", "native", "--release", "cmd/" + name])
    directory = ROOT / "_build/native/release/build/cmd" / name
    return str(next(path for path in (directory / (name + ".exe"), directory / name)
                    if path.is_file()))


def main():
    moon = shutil.which("moon")
    if not moon:
        raise RuntimeError("MoonBit CLI must be installed")
    query, check = build(moon, "query"), build(moon, "check")
    temporary = ROOT / ".tmp"
    temporary.mkdir(exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix="load-diagnostics-", dir=temporary))
    first, second = workspace / "first", workspace / "second"
    first.mkdir()
    second.mkdir()
    report = {"inputs": str(workspace), "cases": [], "passed": False}

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
        if set(data) != {"flags", "diagnostics"}:
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
            text = run([query, str(first), "app", mode], 1)
            if "PC004" not in text or "PC015" in text or str(helper) not in text:
                raise AssertionError(f"Metadata mode lost original diagnostics: {text}")
            report["cases"].append({"case": mode, "text": text})
        text = run([query, str(first), "app", "--cflags", "--explain"], 1)
        if "PC004" not in text or "PC015" in text:
            raise AssertionError("Explanation lost the original diagnostic")
        report["cases"].append({"case": "explain", "text": text})
        text = run([check, str(first)], 1)
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
        report["passed"] = True
    finally:
        output = ROOT / "_build/verification/load-diagnostics.json"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Filesystem dependency diagnostics: {len(report['cases'])} cases passed; {output}")


if __name__ == "__main__":
    main()
