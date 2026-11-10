"""Install the checkout CLI locally and verify its contract outside the repository."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
CHECK_KEYS = {"schema_version", "command", "status", "directories", "file_count",
              "package_count", "package_ids", "diagnostics", "error"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes():
    paths = [ROOT / "moon.mod", ROOT / "moon.pkg", *ROOT.glob("*.mbt")]
    for directory in (ROOT / "cli", ROOT / "cmd"):
        paths.extend(path for path in directory.rglob("*")
                     if path.is_file() and (path.suffix == ".mbt" or path.name == "moon.pkg"))
    return {path.relative_to(ROOT).as_posix(): digest(path) for path in sorted(paths)}


def find_executable(directory, name):
    paths = [directory / (name + suffix) for suffix in ("", ".exe")]
    found = [path.resolve() for path in paths if path.is_file()]
    if len(found) != 1:
        raise AssertionError(f"Expected one installed {name} executable: {found}")
    return found[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--report", type=Path, default=ROOT / "_build/verification/cli.json")
    args = parser.parse_args()
    report_path = args.report.resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report = {"passed": False, "installation": "local checkout", "cases": []}
    started = time.monotonic()

    def save():
        report["elapsed_seconds"] = round(time.monotonic() - started, 3)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    save()
    try:
        moon = shutil.which(args.moon)
        if not moon:
            raise RuntimeError("MoonBit CLI is required; use --moon to specify its executable")
        temporary = ROOT / ".tmp"
        temporary.mkdir(exist_ok=True)
        workspace = Path(tempfile.mkdtemp(prefix="cli-", dir=temporary)).resolve()
        external = Path(tempfile.mkdtemp(prefix="moonpkgconfig-cli-")).resolve()
        if ROOT == external or ROOT in external.parents:
            raise AssertionError("Installed command must be exercised outside the checkout")
        if any((directory / "moon.work").exists() for directory in (external, *external.parents)):
            raise AssertionError("The external test directory must not inherit a moon.work override")
        report.update({"workspace": str(workspace), "external_directory": str(external),
                       "log": str(workspace / "commands.log")})
        before = source_hashes()
        log = workspace / "commands.log"

        def run(command, expected=0, cwd=external, env=None, timeout=30):
            command = list(map(str, command))
            result = subprocess.run(command, cwd=cwd, env=env, capture_output=True,
                                    text=True, encoding="utf-8", errors="replace", timeout=timeout)
            with log.open("a", encoding="utf-8") as output:
                output.write(json.dumps({"command": command, "cwd": str(cwd),
                                         "exit": result.returncode}, ensure_ascii=False) + "\n")
                output.write(result.stdout + result.stderr + "\n")
            if result.returncode != expected:
                raise AssertionError(f"Expected exit {expected}, got {result.returncode}: {command}\n"
                                     + result.stdout + result.stderr)
            return result

        bin_dir = workspace / "installed bin"
        bin_dir.mkdir()
        install_command = [moon, "install", ROOT / "cmd/moonpkgconfig", "--bin", bin_dir]
        run(install_command, cwd=ROOT, timeout=240)
        binary = find_executable(bin_dir, "moonpkgconfig")
        report.update({"install_command": list(map(str, install_command)),
                       "executable": str(binary), "executable_sha256": digest(binary)})
        clean_env = os.environ.copy()
        for key in ("MOON_HOME", "MOONC_OVERRIDE", "MOON_WORK"):
            clean_env.pop(key, None)
        clean_env["PATH"] = ""

        def cli(label, arguments, status=0):
            result = run([binary, *arguments], status, env=clean_env)
            if result.stderr and status != 2:
                raise AssertionError(f"Unexpected stderr for {label}: {result.stderr}")
            report["cases"].append({"case": label, "exit": status, "stderr": result.stderr})
            return result.stdout

        def checked(label, directories, status=0, extra=()):
            arguments = ["check", directories[0]]
            for directory in directories[1:]:
                arguments.extend(["--path", directory])
            text = cli(label, [*arguments, *extra, "--json"], status)
            data = json.loads(text)
            if set(data) != CHECK_KEYS or data["schema_version"] != 1 or data["command"] != "check":
                raise AssertionError(f"Invalid check schema: {data}")
            if data["directories"] != list(map(str, directories)):
                raise AssertionError(f"Directory order changed: {data}")
            if status == 2:
                if (data["status"] not in ("io_error", "usage_error") or not data["error"]
                        or data["file_count"] is not None or data["package_count"] is not None
                        or data["package_ids"] or data["diagnostics"]):
                    raise AssertionError(f"Incomplete check resembles a completed check: {data}")
            elif data["status"] != ("ok" if status == 0 else "diagnostics") or data["error"] is not None:
                raise AssertionError(f"Check status disagrees with exit status: {data}")
            return data

        def pc(directory, name, fields="", prefix=""):
            path = directory / (name + ".pc")
            path.write_text(prefix + f"Name: {name}\nDescription: CLI input\nVersion: 2\n" + fields,
                            encoding="utf-8")
            return path

        first, second, third, empty = [external / name for name in
                                       ("first space", "依赖 中文", "third", "empty")]
        for directory in (first, second, third, empty):
            directory.mkdir()
        cli("global help", ["--help"])
        cli("missing subcommand", [], 2)
        cli("unknown subcommand", ["unknown"], 2)
        for command in ("inspect", "query", "check"):
            text = cli(command + " help", [command, "--help"])
            if "moonpkgconfig " + command not in text or "moon run" in text:
                raise AssertionError("Installed command help refers to a checkout-only entry point")
        data = checked("empty directory", [empty])
        if data["file_count"] != 0 or data["package_count"] != 0 or data["diagnostics"]:
            raise AssertionError(f"Wrong empty directory result: {data}")
        app = pc(first, "app", "Requires: helper >= 2\nLibs: -lapp\nCflags: -I/app\n")
        helper = pc(second, "helper", "Libs: -lhelper\nCflags: -I/helper\n")
        data = checked("missing dependency location", [first], 1)
        if ([problem["code"] for problem in data["diagnostics"]] != ["PC015"]
                or Path(data["diagnostics"][0]["location"]["source"]) != app):
            raise AssertionError(f"Missing dependency diagnostic lost its source: {data}")
        data = checked("multiple directories with spaces and Unicode", [first, second])
        if data["file_count"] != 2 or data["package_ids"] != ["app", "helper"]:
            raise AssertionError(f"Wrong selected package inventory: {data}")
        data = checked("repeated directory keeps selected packages unique", [first, second, second])
        if data["file_count"] != 3 or data["package_count"] != 2 or data["diagnostics"]:
            raise AssertionError(f"Repeated search path changed loader semantics: {data}")
        older = pc(third, "helper", "Libs: -lold\n")
        older.write_text(older.read_text(encoding="utf-8").replace("Version: 2", "Version: 1"), encoding="utf-8")
        checked("earlier valid package shadows later old package", [first, second, third])
        data = checked("reversed paths expose version mismatch", [first, third, second], 1)
        if [problem["code"] for problem in data["diagnostics"]] != ["PC016"]:
            raise AssertionError(f"Search precedence was not preserved: {data}")
        broken = pc(first, "helper", prefix="broken=${missing}\n")
        pc(first, "other", "Requires: helper\n")
        data = checked("broken first package wins and shared errors deduplicate", [first, second], 1)
        problems = data["diagnostics"]
        if (len(problems) != 1 or problems[0]["code"] != "PC004"
                or Path(problems[0]["location"]["source"]) != broken
                or problems[0]["location"]["line"] != 1 or problems[0]["location"]["column"] != 8):
            raise AssertionError(f"Original shared dependency error changed: {data}")
        checked("valid first file shadows later broken file", [second, first])
        data = checked("repeat invalid directory does not duplicate diagnostic", [first, first, second], 1)
        if len(data["diagnostics"]) != 1:
            raise AssertionError(f"Repeated directory duplicated its diagnostic: {data}")
        broken.unlink()
        checked("repair reloads dependency metadata", [first, second])
        private_dir = external / "private"
        private_dir.mkdir()
        pc(private_dir, "private-app", "Requires.private: absent\n")
        data = checked("directory checks include private dependencies", [private_dir], 1)
        if [problem["code"] for problem in data["diagnostics"]] != ["PC015"]:
            raise AssertionError(f"Private dependency not checked: {data}")
        for label, directories in (
            ("missing directory is JSON IO error", [external / "missing"]),
            ("later directory failure is not partial success", [first, second, external / "missing"]),
            ("file supplied as directory is JSON IO error", [app]),
        ):
            data = checked(label, directories, 2)
            if data["status"] != "io_error" or data["error"]["kind"] != "io":
                raise AssertionError(f"Wrong IO error kind: {data}")
        unreadable = external / "file-read-error"
        unreadable.mkdir()
        (unreadable / "directory.pc").mkdir()
        checked("pc file read failure is not empty success", [unreadable], 2)
        checked("unknown check option is structured usage error", [first], 2, ["--unknown"])
        usage = json.loads(cli("missing path operand is structured usage error",
                               ["check", first, "--path", "--json"], 2))
        if set(usage) != CHECK_KEYS or usage["status"] != "usage_error":
            raise AssertionError(f"Wrong usage error schema: {usage}")

        target = workspace / "legacy-build"
        for name in ("query", "inspect", "check"):
            run([moon, "build", "--target", "native", "--release", "--target-dir", target,
                 "cmd/" + name], cwd=ROOT, timeout=180)
        legacy = {name: find_executable(target / "native/release/build/cmd" / name, name)
                  for name in ("query", "inspect", "check")}
        parity = [
            ("query", [first, "app", "--path", second, "--libs", "--json"], 0),
            ("query", [first, "app", "--path", second, "--cflags", "--explain"], 0),
            ("query", [first, "app", "--libs", "--json"], 1),
            ("query", [second, "helper", "--modversion"], 0),
            ("query", [second, "helper", "--exists"], 0),
            ("inspect", [app, "--json"], 0),
            ("inspect", [app], 0),
            ("inspect", [external / "missing.pc", "--json"], 2),
            ("check", [first], 1),
            ("check", [first, "--path", second, "--json"], 0),
        ]
        for index, (name, arguments, status) in enumerate(parity):
            original = run([legacy[name], *arguments], status, env=clean_env)
            actual = cli(f"legacy {name} parity {index + 1}", [name, *arguments], status)
            if actual != original.stdout:
                raise AssertionError(f"Installed {name} differs from the legacy entry point")
        report["source_unchanged"] = before == source_hashes()
        if not report["source_unchanged"]:
            raise AssertionError("CLI installation or verification changed project source")
        report["passed"] = True
    except (OSError, RuntimeError, ValueError, AssertionError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
        raise
    finally:
        save()
    print(f"Installed checkout CLI: {len(report['cases'])} cases passed; {report_path}")


if __name__ == "__main__":
    main()
