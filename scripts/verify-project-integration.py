"""Verify ordinary MoonBit builds using the experimental multi-package hook."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources(directory):
    return {path.relative_to(directory).as_posix(): digest(path) for path in sorted(directory.rglob("*"))
            if path.is_file() and not any(part in ("_build", ".mooncakes", "__pycache__")
                                          for part in path.relative_to(directory).parts)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepared-report", type=Path, help="reuse a successful native walkthrough/dependency report")
    parser.add_argument("--zlib-pc-dir", type=Path)
    parser.add_argument("--expat-pc-dir", type=Path)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--cmake", default="cmake")
    parser.add_argument("--cc")
    parser.add_argument("--zlib-archive", type=Path)
    parser.add_argument("--expat-archive", type=Path)
    parser.add_argument("--msvc-lib", action="append", default=[])
    parser.add_argument("--report", type=Path, default=ROOT / "_build/verification/project-integration.json")
    args = parser.parse_args()
    if bool(args.zlib_pc_dir) != bool(args.expat_pc_dir):
        parser.error("Supply both installed metadata directories")
    if args.prepared_report and args.zlib_pc_dir:
        parser.error("Choose --prepared-report or explicit metadata directories")
    if (args.prepared_report or args.zlib_pc_dir) and (args.zlib_archive or args.expat_archive):
        parser.error("Archives are only used when preparing dependencies")
    moon = shutil.which(args.moon)
    if not moon:
        parser.error("MoonBit executable not found")
    moon = str(Path(moon).resolve())
    report = args.report.resolve()
    report.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    evidence = {"dependency": "xmyd0915/moonpkgconfig@0.3.1", "platform": sys.platform,
                "passed": False, "cases": []}

    def save():
        evidence["elapsed_seconds"] = round(time.monotonic() - started, 3)
        report.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    save()
    try:
        mappings = list(args.msvc_lib)
        if args.zlib_pc_dir:
            directories = {"zlib": args.zlib_pc_dir.resolve(), "expat": args.expat_pc_dir.resolve()}
        else:
            prepared_report = args.prepared_report
            if not prepared_report:
                prepared_report = report.parent / "project-dependencies.json"
                command = [sys.executable, str(ROOT / "scripts/prepare-native.py"), "--moon", moon,
                           "--cmake", args.cmake, "--report", str(prepared_report)]
                if args.cc:
                    command += ["--cc", args.cc]
                for name in ("zlib", "expat"):
                    archive = getattr(args, name + "_archive")
                    if archive:
                        command += ["--" + name + "-archive", str(archive.resolve())]
                subprocess.run(command, cwd=ROOT, check=True, timeout=1200)
            prepared = json.loads(prepared_report.read_text(encoding="utf-8"))
            if not prepared.get("passed"):
                raise RuntimeError("Dependency preparation report did not pass")
            source = prepared.get("preparation", prepared)
            selected = prepared.get("search_directories") or {
                name: source[name + "_pc_dir"] for name in ("zlib", "expat")}
            directories = {name: Path(selected[name]).resolve() for name in ("zlib", "expat")}
            if not mappings:
                mappings = source.get("zlib_msvc_lib", [])
            evidence["prepared_report"] = str(prepared_report.resolve())
        installed = {name: directory / (name + ".pc") for name, directory in directories.items()}
        original_hashes = {name: digest(path) for name, path in installed.items()}
        working = Path(tempfile.mkdtemp(prefix="project-integration-")).resolve()
        consumer = working / "project with spaces"
        template = ROOT / "examples/project-integration"
        shutil.copytree(template, consumer, ignore=shutil.ignore_patterns("_build", ".mooncakes", "__pycache__"))
        baseline = sources(consumer)
        if baseline != sources(template):
            raise RuntimeError("Standalone integration differs from the source example")
        application = consumer / "app"
        pc_directory = working / "metadata with spaces"
        pc_directory.mkdir()
        pc_files = {}
        native_files = []
        def copy_native(source, destination):
            original_hash = digest(source)
            shutil.copy2(source, destination)
            if digest(destination) != original_hash:
                raise RuntimeError("Relocated native file differs from its installation")
            native_files.append({"source": str(source), "copy": str(destination), "sha256": original_hash})

        for name, source in installed.items():
            target = pc_directory / source.name
            metadata = source.read_text(encoding="utf-8")
            # The prepared libraries have explicit installation prefixes. Use
            # independent relocated copies to exercise spaces in -I/-L as well
            # as in project and metadata paths, without editing the originals.
            prefix_match = re.search(r"^prefix=(.+)$", metadata, re.MULTILINE)
            if not prefix_match or not Path(prefix_match[1].strip()).is_absolute():
                raise RuntimeError("Verification requires an explicit absolute installation prefix")
            prefix = Path(prefix_match[1].strip()).resolve()
            relocated = working / (name + " installation with spaces")
            # Copy only the fixture's headers and static archives. An explicit
            # installation might live under /usr; never copy the entire prefix.
            (relocated / "include").mkdir(parents=True)
            (relocated / "lib").mkdir()
            headers = ("zlib.h", "zconf.h") if name == "zlib" else ("expat.h", "expat_external.h")
            for header in headers:
                copy_native(prefix / "include" / header, relocated / "include" / header)
            mapped = dict(value.split("=", 1) for value in mappings)
            library_names = re.findall(r"(?:^|\s)-l([A-Za-z0-9_+.-]+)", metadata)
            for library in library_names:
                filename = mapped.get(library, library + ".lib") if os.name == "nt" else "lib" + library + ".a"
                copy_native(prefix / "lib" / filename, relocated / "lib" / filename)
            metadata = metadata.replace(prefix.as_posix(), relocated.as_posix())
            metadata = metadata.replace(str(prefix), relocated.as_posix())
            for variable in ("includedir", "libdir", "sharedlibdir"):
                flag = "-I" if variable == "includedir" else "-L"
                metadata = metadata.replace(flag + "${" + variable + "}", flag + '"${' + variable + '}"')
            target.write_text(metadata, encoding="utf-8")
            pc_files[name] = target
        originals = {name: path.read_text(encoding="utf-8") for name, path in pc_files.items()}
        evidence.update({"consumer": str(consumer), "source_sha256": baseline,
                         "metadata_sha256": original_hashes, "metadata": {k: str(v) for k, v in installed.items()},
                         "native_files": native_files})

        def execute(label, command, expected=0, directory=application, dry=False):
            print(label, flush=True)
            result = subprocess.run(command, cwd=directory, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace", timeout=180)
            # --dry-run includes the compiler's environment. Do not persist any
            # raw dry-run output; retain only the two validated link commands.
            stdout = "" if dry else result.stdout
            stderr = "" if dry else result.stderr
            evidence["cases"].append({"case": label, "command": command, "exit": result.returncode,
                                      "stdout": stdout, "stderr": stderr})
            if (expected == 0 and result.returncode != 0) or (expected != 0 and result.returncode == 0):
                raise RuntimeError(f"{label}: unexpected exit {result.returncode}\n{stdout}{stderr}")
            return result

        configure = [sys.executable, str(consumer / "configure.py"), "--moon", moon,
                     "--pc-dir", str(pc_directory)]
        for mapping in mappings:
            configure += ["--msvc-lib", mapping]
        execute("bootstrap independent registry planner", configure, directory=consumer)
        configured = json.loads((application / "_build/native-config.json").read_text(encoding="utf-8"))
        planner_hash = configured["planner_sha256"]
        command = [moon, "build", "--target", "native", "--deny-warn"]
        execute("build unchanged multi-package project", command)
        execute("test library packages with inherited links", [moon, "test", "--target", "native", "--deny-warn"])
        expected_outputs = {"checksum": "crc=3421780262 custom=7", "combined": "crc=3421780262 xml=true custom=7,11"}
        for name, expected_output in expected_outputs.items():
            result = execute("run " + name, [moon, "run", "--target", "native", "--deny-warn", "cmd/" + name])
            if expected_output not in result.stdout:
                raise RuntimeError("Native results or original custom C settings differ")
        good_plan = json.loads((application / "_build/native-plan.json").read_text(encoding="utf-8"))
        if not good_plan["passed"] or not any(flag["value"] == "-DXML_STATIC"
                for item in good_plan["plans"] for flag in item["plan"]["cflags"]["flags"]):
            raise RuntimeError("Missing static Expat definition from metadata")
        evidence["initial_plan"] = good_plan

        # Inspect generated link commands in addition to executing the programs.
        # This proves Expat is absent from the zlib-only consumer's link step.
        dry = execute("inspect package-specific linking", command + ["--dry-run"], dry=True)
        commands = [line for line in dry.stdout.splitlines() if line and not line.startswith(" ")]
        def linker(name):
            fragment = "cmd/" + name + "/" + name
            lines = []
            for line in commands:
                if fragment not in line.replace("\\", "/") or "link-core" in line:
                    continue
                arguments = shlex.split(line)
                outputs = [value[3:] for value in arguments if value.startswith("/Fe")]
                outputs += [arguments[i + 1] for i, value in enumerate(arguments[:-1]) if value == "-o"]
                if any(Path(value).name in (name, name + ".exe") for value in outputs):
                    lines.append(line)
            if len(lines) != 1:
                raise RuntimeError(f"Could not identify {name} linker command: {lines}")
            return lines[0]
        only_zlib, combined = linker("checksum"), linker("combined")
        zlib_token = "zlibstatic.lib" if os.name == "nt" else "-lz"
        expat_token = "libexpatMT.lib" if os.name == "nt" else "-lexpat"
        if zlib_token not in only_zlib or expat_token in only_zlib or zlib_token not in combined or expat_token not in combined:
            raise RuntimeError("Native links did not follow package imports")
        evidence["link_commands"] = {"checksum": only_zlib, "combined": combined}

        pc_files["zlib"].write_text("broken=${missing}\n" + originals["zlib"], encoding="utf-8")
        failure = execute("diagnose changed metadata without reconfigure", command, 1)
        failed = json.loads((application / "_build/native-plan.json").read_text(encoding="utf-8"))
        location = str(pc_files["zlib"]) + ":1:8"
        if failed["passed"] or "PC004" not in failed.get("error", "") or location not in failed.get("error", ""):
            raise RuntimeError("The hook reused a stale plan or lost the original source location")
        evidence["damaged_plan"] = failed
        pc_files["zlib"].write_text(originals["zlib"], encoding="utf-8")
        execute("repair and rebuild without reconfigure", command)

        pc_files["zlib"].write_text(originals["zlib"].replace("Cflags:", "Cflags: -DMETADATA_REVISION=9", 1), encoding="utf-8")
        revised = execute("recompute changed compiler arguments", [moon, "run", "--target", "native", "--deny-warn", "cmd/checksum"])
        if "crc=3421780262 custom=16" not in revised.stdout:
            raise RuntimeError("Changed metadata did not recompile the existing C stub")
        evidence["changed_plan"] = json.loads((application / "_build/native-plan.json").read_text(encoding="utf-8"))
        pc_files["zlib"].write_text(originals["zlib"], encoding="utf-8")
        execute("restore original flags and library tests", [moon, "test", "--target", "native", "--deny-warn"])

        pc_files["zlib"].write_text(originals["zlib"].replace("Cflags:", "Cflags: -funsupported-hook-option", 1), encoding="utf-8")
        rejected = execute("reject unsupported adapter option", command, 1)
        if "Unsupported native option '-funsupported-hook-option'" not in rejected.stdout + rejected.stderr:
            raise RuntimeError("Unsupported native option was not identified")
        pc_files["zlib"].write_text(originals["zlib"], encoding="utf-8")
        execute("final repaired native build", command)
        if digest(Path(configured["planner"])) != planner_hash:
            raise RuntimeError("Build hook rebuilt the bootstrap planner")
        if sources(consumer) != baseline:
            raise RuntimeError("Builds changed source code or existing manifests")
        if any(digest(path) != original_hashes[name] for name, path in installed.items()):
            raise RuntimeError("Original installed metadata changed")
        if any(digest(Path(item["source"])) != item["sha256"] or digest(Path(item["copy"])) != item["sha256"]
               for item in native_files):
            raise RuntimeError("Installed or relocated headers/static libraries changed")
        evidence.update({"source_preserved": True, "metadata_preserved": True, "planner_preserved": True,
                         "space_paths": {"project": True, "metadata": True, "native_installations": True}, "passed": True})
    except Exception as error:
        evidence["error"] = str(error)
        raise
    finally:
        save()
    print(f"Project integration passed; {report}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
