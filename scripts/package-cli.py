"""Build a standalone CLI archive and verify its extracted executable."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess
import tempfile
import time
import zipfile


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "_build/cli"
REPORT = ROOT / "_build/verification/cli-package.json"
ARTIFACT = re.compile(r"moonpkgconfig-[0-9a-f]{12}(?:-dirty)?-(?:windows|linux)-(?:x86_64|aarch64)\.zip(?:\.sha256)?")
TEXT_FILES = {"LICENSE", "USAGE.txt", "build-info.json", "SHA256SUMS", "THIRD-PARTY-NOTICES.txt"}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def run(command, cwd=ROOT, env=None, expected=0, timeout=240):
    result = subprocess.run(list(map(str, command)), cwd=cwd, env=env,
                            capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=timeout)
    if result.returncode != expected:
        # Build output may contain machine paths or environment details. Neither
        # it nor the command is copied to the distributable machine report.
        raise RuntimeError("Command exited with {} instead of {}".format(result.returncode, expected))
    return result


def git(*arguments):
    return run(["git", "-c", "safe.directory=" + ROOT.as_posix(), *arguments]).stdout.strip()


def git_state():
    commit = git("rev-parse", "HEAD")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Expected a full Git source commit")
    return commit, bool(git("status", "--porcelain", "--untracked-files=normal"))


def compiler_sources():
    paths = [ROOT / "moon.mod", ROOT / "moon.pkg", *ROOT.glob("*.mbt")]
    for directory in (ROOT / "cli", ROOT / "cmd"):
        paths.extend(path for path in directory.rglob("*")
                     if path.is_file() and (path.suffix == ".mbt" or path.name == "moon.pkg"))
    records = [(path.relative_to(ROOT).as_posix(), sha256(path.read_bytes())) for path in sorted(paths)]
    return sha256(json.dumps(records, separators=(",", ":")).encode("utf-8"))


def platform_name():
    system = {"Windows": "windows", "Linux": "linux"}.get(platform.system())
    architecture = {"amd64": "x86_64", "x86_64": "x86_64", "aarch64": "aarch64", "arm64": "aarch64"}.get(platform.machine().lower())
    if system is None or architecture is None:
        raise ValueError("Trial packages currently support Linux and Windows on x86_64 or aarch64")
    return system, architecture


def version_line(command, env):
    lines = run(command, env=env).stdout.splitlines()
    line = next((line.strip() for line in lines if line.strip()), "")
    if not line or not re.fullmatch(r"[A-Za-z0-9_.+() :,-]+", line):
        raise ValueError("Unexpected tool version format")
    return line


def module_version(path):
    match = re.search(r'^version\s*=\s*"([A-Za-z0-9_.+-]+)"', path.read_text(encoding="utf-8"), re.MULTILINE)
    if not match:
        raise ValueError("Dependency version is unavailable")
    return match[1]


def third_party_notices(toolchain):
    core = toolchain / "lib/core"
    apache = (core / "LICENSE").read_text(encoding="utf-8")
    notice = (core / "NOTICE").read_text(encoding="utf-8")
    if "Apache License" not in apache or "Version 2.0" not in apache or not notice.strip():
        raise ValueError("The actual toolchain must provide its Apache license and notice")
    x_root = ROOT / ".mooncakes/moonbitlang/x"
    versions = {"moonbitlang/core": module_version(core / "moon.mod"),
                "moonbitlang/x": module_version(x_root / "moon.mod")}
    headers = []
    for source in ("fs/fs_native.mbt", "path/path.mbt", "sys/sys.mbt"):
        header = []
        for line in (x_root / source).read_text(encoding="utf-8").splitlines():
            if not line.startswith("//") or line.startswith("///|"):
                break
            header.append(line)
        text = "\n".join(header)
        if "Copyright" not in text or "Apache License" not in text:
            raise ValueError("Dependency copyright/license header is missing")
        if text not in headers:
            headers.append(text)
    text = (
        "Third-party materials used by this CLI build\n\n"
        "moonbitlang/core " + versions["moonbitlang/core"] + "\n"
        "https://github.com/moonbitlang/core\n"
        "The LICENSE and NOTICE below are copied from the selected toolchain.\n\n"
        "moonbitlang/x " + versions["moonbitlang/x"] + "\n"
        "https://github.com/moonbitlang/x\n"
        "The copyright/license headers below are preserved from the installed\n"
        "fs, path and sys sources. They are not a complete list of authors.\n\n"
        + "\n\n".join(headers) + "\n\n"
        "=== Apache License 2.0 (core/LICENSE; also applies to moonbitlang/x) ===\n\n"
        + apache + "\n=== Complete toolchain core/NOTICE ===\n\n" + notice
    )
    return text.encode("utf-8"), versions


def usage(binary, system, architecture):
    command = ".\\" + binary if system == "windows" else "./" + binary
    scope = ("Windows native build; use the matching architecture."
             if system == "windows" else
             "Linux native build: verified on the CI Ubuntu runner of the same\n"
             "architecture only. Other distributions, libc versions and systems\n"
             "are not promised to work. The binary is not claimed to be static.")
    return ("MoonPkgConfig standalone CLI\n\n"
            "The module version, exact source commit, dirty state and build tool versions\n"
            "are recorded in build-info.json. No MoonBit installation is needed\n"
            "for the verified commands after extraction.\n\n"
            "Platform: " + system + "; architecture: " + architecture + "\n" + scope + "\n\n"
            "Verify the downloaded ZIP using its adjacent .zip.sha256 file.\n"
            "SHA256SUMS inside the ZIP covers every other extracted file.\n"
            "Linux: extract with a tool that preserves executable permissions,\n"
            "or run chmod +x moonpkgconfig after extraction. Python's standard\n"
            "ZIP extractor does not restore these permissions automatically.\n\n"
            + command + " --version\n"
            + command + " --help\n"
            + command + " inspect path/to/example.pc --json\n"
            + command + " query path/to/pkgconfig package-name --libs --json\n"
            + command + " check path/to/pkgconfig --json\n\n"
            "Replace the example paths and package name with your own metadata.\n"
            "Exit codes: 0 success; 1 diagnostics, missing query result or unmet\n"
            "query condition; 2 usage or IO error.\n"
            "See LICENSE and THIRD-PARTY-NOTICES.txt for license information.\n").encode("utf-8")


def create_archive(path, files, binary):
    checksums = "".join(sha256(data) + "  " + name + "\n" for name, data in sorted(files.items()))
    files = dict(files, SHA256SUMS=checksums.encode("ascii"))
    if set(files) != TEXT_FILES | {binary}:
        raise ValueError("Unexpected archive content")
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | (0o755 if name == binary else 0o644)) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    return files


def unpack_checked(path, destination, expected, binary):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or set(names) != set(expected):
            raise ValueError("Archive contains unexpected or duplicate entries")
        for entry in archive.infolist():
            if Path(entry.filename).name != entry.filename or "/" in entry.filename or "\\" in entry.filename:
                raise ValueError("Archive entry is not a flat filename")
            if not stat.S_ISREG(entry.external_attr >> 16) or entry.is_dir():
                raise ValueError("Archive entry is not a regular file")
            data = archive.read(entry)
            if data != expected[entry.filename]:
                raise ValueError("Archive file content changed")
            (destination / entry.filename).write_bytes(data)
        expected_sums = "".join(sha256(data) + "  " + name + "\n"
                                for name, data in sorted(expected.items()) if name != "SHA256SUMS")
        if (destination / "SHA256SUMS").read_text(encoding="ascii") != expected_sums:
            raise ValueError("Archive checksums differ")
        executable_mode = archive.getinfo(binary).external_attr >> 16
        if executable_mode & 0o111 != 0o111:
            raise ValueError("ZIP does not preserve executable permissions")
    if os.name != "nt":
        (destination / binary).chmod(0o755)


def verify_extracted(directory, binary, cases):
    clean_env = {key: value for key, value in os.environ.items() if not key.upper().startswith("MOON")}
    clean_env["PATH"] = ""
    for key in ("LD_LIBRARY_PATH", "LD_PRELOAD", "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES"):
        clean_env.pop(key, None)

    def execute(label, arguments, expected=0, as_json=True):
        result = run([directory / binary, *arguments], cwd=directory,
                     env=clean_env, expected=expected, timeout=30)
        if expected < 2 and result.stderr:
            raise AssertionError("Unexpected stderr in " + label)
        data = json.loads(result.stdout) if as_json else result.stdout
        cases.append({"case": label, "exit": result.returncode})
        return data

    good, bad = directory / "metadata files", directory / "broken metadata"
    good.mkdir()
    bad.mkdir()
    (good / "app.pc").write_text("Name: app\nDescription: archive smoke input\nVersion: 2.0\n"
                                 "Requires: helper >= 2\nLibs: -lapp\nCflags: -I\"/sdk/include path\"\n", encoding="utf-8")
    (good / "helper.pc").write_text("Name: helper\nDescription: archive dependency\nVersion: 2.1\nLibs: -lhelper\n", encoding="utf-8")
    (bad / "broken.pc").write_text("broken=${missing}\nName: broken\nDescription: broken input\nVersion: 1\n", encoding="utf-8")
    help_text = execute("help without MoonBit environment", ["--help"], as_json=False)
    if any(command not in help_text for command in ("inspect", "query", "check")):
        raise AssertionError("Global help omits an entry point")
    version = execute("version matches module manifest", ["--version"], as_json=False)
    if version.strip() != "moonpkgconfig " + module_version(ROOT / "moon.mod"):
        raise AssertionError("Executable and module versions differ")
    inspected = execute("inspect valid metadata", ["inspect", "metadata files/app.pc", "--json"])
    if inspected["diagnostics"] or not any(entry["name"] == "Version" and entry["value"] == "2.0" for entry in inspected["entries"]):
        raise AssertionError("Inspection result differs")
    queried = execute("query dependency order", ["query", "metadata files", "app", "--libs", "--json"])
    if queried["diagnostics"] or [flag["value"] for flag in queried["flags"]] != ["-lapp", "-lhelper"]:
        raise AssertionError("Dependency link arguments differ")
    quoted = execute("query preserves argument boundary", ["query", "metadata files", "app", "--cflags", "--json"])
    if quoted["diagnostics"] or [flag["value"] for flag in quoted["flags"]] != ["-I/sdk/include path"]:
        raise AssertionError("Quoted path argument differs")
    checked = execute("check package directory", ["check", "metadata files", "--json"])
    if (checked["diagnostics"] or checked["status"] != "ok" or checked["file_count"] != 2
            or checked["package_count"] != 2 or checked["package_ids"] != ["app", "helper"]):
        raise AssertionError("Directory inventory differs")
    for command, arguments in (
        ("inspect", ["broken metadata/broken.pc"]),
        ("query", ["broken metadata", "broken", "--libs"]),
        ("check", ["broken metadata"]),
    ):
        data = execute(command + " rejects bad metadata", [command, *arguments, "--json"], 1)
        problems = data["diagnostics"]
        if (len(problems) != 1 or problems[0]["code"] != "PC004"
                or problems[0]["location"]["line"] != 1 or problems[0]["location"]["column"] != 8):
            raise AssertionError("Bad metadata lost its original diagnostic")
        if command == "query" and data["flags"]:
            raise AssertionError("Failed query returned successful flags")
    for command, arguments in (
        ("inspect", ["missing.pc"]),
        ("query", ["missing directory", "app", "--libs"]),
        ("check", ["missing directory"]),
    ):
        data = execute(command + " rejects missing input", [command, *arguments, "--json"], 2)
        if data["status"] != "io_error" or not data["error"]:
            raise AssertionError("IO failure resembles success")
    return cases


def clear_previous_artifacts():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if OUTPUT.resolve() != OUTPUT:
        raise ValueError("Generated output directory must not redirect outside its checkout path")
    for path in OUTPUT.iterdir():
        # Only this script's flat, generated trial filenames are owned here.
        if ARTIFACT.fullmatch(path.name):
            if path.is_symlink() or not path.is_file():
                raise ValueError("Unexpected generated artifact type")
            path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--require-clean", action="store_true", help="reject tracked or untracked source changes (CI)")
    args = parser.parse_args()
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    report = {"schema_version": 1, "passed": False, "distribution": "standalone CLI", "cases": []}
    started = time.monotonic()
    REPORT.write_text(json.dumps(report) + "\n", encoding="utf-8")
    try:
        clear_previous_artifacts()
        commit, dirty = git_state()
        if args.require_clean and dirty:
            raise ValueError("CI packaging requires a clean Git worktree")
        system, architecture = platform_name()
        moon_path = shutil.which(args.moon)
        if moon_path is None:
            raise ValueError("MoonBit executable not found")
        moon = Path(moon_path).resolve()
        toolchain = moon.parent.parent
        moonc = moon.parent / ("moonc.exe" if os.name == "nt" else "moonc")
        build_env = {key: value for key, value in os.environ.items() if not key.upper().startswith("MOON")}
        build_env["MOON_HOME"] = str(toolchain)
        build_env["PATH"] = str(moon.parent) + os.pathsep + build_env.get("PATH", "")
        before = compiler_sources()
        info = {"schema_version": 1, "distribution": "standalone CLI", "source_commit": commit,
                "module_version": module_version(ROOT / "moon.mod"),
                "dirty": dirty, "source_sha256": before, "platform": system, "arch": architecture,
                "moon_version": version_line([moon, "version"], build_env),
                "moonc_version": version_line([moonc, "-v"], build_env)}
        report["build_info"] = info
        binary = "moonpkgconfig.exe" if system == "windows" else "moonpkgconfig"
        archive_name = "moonpkgconfig-" + commit[:12] + ("-dirty" if dirty else "") + "-" + system + "-" + architecture + ".zip"
        # TemporaryDirectory removes only its own newly-created directory. All
        # packaging and extraction happens outside the checkout.
        with tempfile.TemporaryDirectory(prefix="moonpkgconfig trial ") as temporary:
            workspace = Path(temporary).resolve()
            if (workspace.parent != Path(tempfile.gettempdir()).resolve()
                    or workspace == ROOT or ROOT in workspace.parents):
                raise ValueError("Temporary extraction directory must be outside the checkout")
            installed = workspace / "installed command"
            extracted = workspace / "extracted package with spaces"
            installed.mkdir()
            extracted.mkdir()
            run([moon, "install", ROOT / "cmd/moonpkgconfig", "--bin", installed], env=build_env)
            candidates = list(installed.iterdir())
            if len(candidates) != 1 or candidates[0].name != binary or not candidates[0].is_file():
                raise ValueError("Unexpected moon install output")
            notices, dependencies = third_party_notices(toolchain)
            info["dependencies"] = dependencies
            after_commit, after_dirty = git_state()
            if compiler_sources() != before or after_commit != commit or after_dirty != dirty:
                raise ValueError("Source state changed while the CLI was being built")
            files = {binary: (installed / binary).read_bytes(), "LICENSE": (ROOT / "LICENSE").read_bytes(),
                     "USAGE.txt": usage(binary, system, architecture), "THIRD-PARTY-NOTICES.txt": notices,
                     "build-info.json": (json.dumps(info, sort_keys=True, indent=2) + "\n").encode("utf-8")}
            staged = workspace / archive_name
            expected = create_archive(staged, files, binary)
            unpack_checked(staged, extracted, expected, binary)
            verify_extracted(extracted, binary, report["cases"])
            if any((extracted / name).read_bytes() != data for name, data in expected.items()):
                raise ValueError("Executing the extracted CLI changed packaged files")
            archive_digest = sha256(staged.read_bytes())
            # No downloadable output is created until all extracted-binary
            # checks pass. Failed runs therefore cannot publish a stale ZIP.
            destination = OUTPUT / archive_name
            shutil.copyfile(staged, destination)
            (OUTPUT / (archive_name + ".sha256")).write_text(archive_digest + "  " + archive_name + "\n", encoding="ascii")
            report.update({"passed": True, "archive": archive_name, "archive_sha256": archive_digest,
                           "executable": binary, "executable_sha256": sha256(files[binary]),
                           "files": [{"name": name, "sha256": sha256(data), "size": len(data)}
                                     for name, data in sorted(expected.items())],
                           "verification": {"outside_checkout": True, "extraction_path_has_spaces": True,
                                            "moon_environment_removed": True, "path_empty": True,
                                            "archive_allowlist_checked": True, "source_unchanged": True}})
    except Exception as error:
        # Error details stay on the invoking terminal; the public report never
        # includes paths, commands, subprocess output, or inherited environment.
        report["error"] = {"kind": type(error).__name__, "message": "CLI trial packaging did not complete"}
        clear_previous_artifacts()
        raise
    finally:
        report["elapsed_seconds"] = round(time.monotonic() - started, 3)
        REPORT.write_text(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print("Standalone CLI package verified: " + report["archive"])


if __name__ == "__main__":
    main()
