#!/usr/bin/env python3
"""Plan and build a root-package native application with MoonCakes 0.3.0."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent
MODULE = "xmyd0915/moonpkgconfig"
VERSION = "0.3.0"
NAME = r"[A-Za-z0-9_+][A-Za-z0-9_+.-]*"


def run(command, directory, status=0):
    result = subprocess.run(command, cwd=directory, text=True, encoding="utf-8",
                            errors="replace", capture_output=True)
    if result.returncode != status:
        raise RuntimeError(f"Expected exit {status}, got {result.returncode}: "
                           f"{shlex.join(command)}\n{result.stdout}{result.stderr}")
    return result.stdout.strip()


def msvc_arguments(flags, compile_mode, mappings):
    prefixes = {"-I": "/I", "-D": "/D", "-U": "/U"} if compile_mode else {
        "-L": "/LIBPATH:", "-l": "",
    }
    output = []
    index = 0
    while index < len(flags):
        flag = flags[index]
        value = flag["value"]
        prefix = value[:2]
        if prefix not in prefixes:
            raise RuntimeError(f"Unsupported MSVC option {value!r} from {flag['package']}:{flag['field']}")
        operand = value[2:]
        if not operand:
            index += 1
            if index >= len(flags) or any(flags[index][key] != flag[key] for key in (
                "package", "field", "location",
            )) or not flags[index]["value"] or flags[index]["value"].startswith("-"):
                raise RuntimeError(f"Missing operand for {prefix}")
            operand = flags[index]["value"]
        if prefix == "-l":
            if not re.fullmatch(NAME, operand):
                raise RuntimeError(f"Unsupported MSVC library {operand!r}")
            output.append(mappings.get(operand, operand + ".lib"))
        else:
            output.append(prefixes[prefix] + operand)
        index += 1
    return ["/utf-8", "/MT", *output] if compile_mode else (["/link", *output] if output else [])


def diagnostics(plan):
    unique = []
    for section in ("cflags", "libs"):
        for problem in plan[section]["diagnostics"]:
            if problem not in unique:
                unique.append(problem)
    return unique


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True, help="application consumer.json")
    parser.add_argument("--pc-dir", type=Path, action="append", default=[], help="ordered dependency search directory")
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--cc", help="POSIX C compiler; Windows uses MoonBit's MSVC discovery")
    parser.add_argument("--msvc-lib", action="append", default=[], metavar="NAME=FILE.lib")
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--run", action="store_true", help="also run the built application")
    args = parser.parse_args()
    if args.plan_only and args.run:
        parser.error("--plan-only and --run cannot be combined")
    config_path = args.config.resolve()
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if not isinstance(config, dict) or set(config) != {"package", "static", "stubs", "imports"}:
        parser.error("consumer.json requires package, static, stubs and imports")
    if not isinstance(config["package"], str) or not re.fullmatch(NAME, config["package"]) or type(config["static"]) is not bool:
        parser.error("package must be a module identifier and static must be a boolean")
    if not isinstance(config["stubs"], list) or not config["stubs"] or any(
        not isinstance(stub, str) or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*\.(?:c|cc|cpp)", stub)
        for stub in config["stubs"]
    ) or len(set(config["stubs"])) != len(config["stubs"]):
        parser.error("stubs must be unique C/C++ filenames in the application directory")
    if not isinstance(config["imports"], list) or any(
        not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_./+-]+", name)
        for name in config["imports"]
    ):
        parser.error("imports must contain MoonBit package paths")
    application = config_path.parent
    for filename in ("moon.mod", "main.mbt", config["package"] + ".pc", *config["stubs"]):
        if not (application / filename).is_file():
            parser.error(f"Application is missing {filename}")
    directories = [application, *[path.resolve() for path in args.pc_dir]]
    if not all(path.is_dir() for path in directories):
        parser.error("Every explicit search directory must exist")
    moon = shutil.which(args.moon)
    compiler_name = args.cc or (None if os.name == "nt" else "cc")
    compiler = shutil.which(compiler_name) if compiler_name else None
    if not moon or (compiler_name and not compiler):
        parser.error("MoonBit and the selected compiler must be installed")
    if os.name == "nt" and compiler and Path(compiler).stem.lower() not in ("cl", "clang-cl"):
        parser.error("Windows requires an MSVC-compatible compiler")
    mappings = {}
    for mapping in args.msvc_lib:
        name, separator, filename = mapping.partition("=")
        if os.name != "nt" or not separator or not re.fullmatch(NAME, name) or not re.fullmatch(NAME + r"\.lib", filename) or name in mappings:
            parser.error("--msvc-lib requires a unique NAME=FILE.lib mapping on Windows")
        mappings[name] = filename
    for parent in (ROOT, *ROOT.parents, application, *application.parents):
        if (parent / "moon.work").exists():
            raise RuntimeError("Run the template and application outside moon.work overrides")
    run([moon, "update"], ROOT)
    run([moon, "build", "--target", "native", "--deny-warn", "cmd/plan"], ROOT)
    installed = ROOT / ".mooncakes" / MODULE / "moon.mod"
    if not installed.is_file() or not re.search(r'^version\s*=\s*"0\.3\.0"', installed.read_text(encoding="utf-8"), re.MULTILINE):
        raise RuntimeError("The planner must use MoonCakes MoonPkgConfig 0.3.0")
    working = Path(tempfile.mkdtemp(prefix="consumer-", dir=ROOT / "_build"))
    evidence = {"dependency": MODULE + "@" + VERSION, "config": config,
                "search_directories": list(map(str, directories)), "built": False}
    report = working / "evidence.json"
    try:
        command = [moon, "run", "--target", "native", "--deny-warn", "cmd/plan",
                   config["package"], "static" if config["static"] else "dynamic", *map(str, directories)]
        result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", capture_output=True)
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stdout + result.stderr)
        plan = json.loads(result.stdout)
        evidence.update({"plan": plan, "plan_exit": result.returncode})
        problems = diagnostics(plan)
        if bool(problems) != (result.returncode == 1):
            raise RuntimeError("Plan status disagrees with diagnostics")
        print(f"Dependency: {MODULE}@{VERSION} (MoonCakes)", flush=True)
        if problems:
            for problem in problems:
                at = problem["location"]
                print(f"{problem['code']} {at['source']}:{at['line']}:{at['column']} {problem['message']}", flush=True)
            return 1
        for section in ("cflags", "libs"):
            for flag in plan[section]["flags"]:
                at = flag["location"]
                print(f"{flag['value']} <- {flag['package']}:{flag['field']} [{at['source']}:{at['line']}]", flush=True)
        if args.plan_only:
            return 0
        compile_flags = plan["cflags"]["flags"]
        link_flags = plan["libs"]["flags"]
        if os.name == "nt":
            compile_values = msvc_arguments(compile_flags, True, mappings)
            link_values = msvc_arguments(link_flags, False, mappings)
        else:
            compile_values = [flag["value"] for flag in compile_flags]
            link_values = [flag["value"] for flag in link_flags]
        native = {"cc-flags": shlex.join(compile_values), "stub-cc-flags": shlex.join(compile_values),
                  "cc-link-flags": shlex.join(link_values)}
        if compiler:
            native.update({"cc": compiler, "stub-cc": compiler})
        destination = working / "application"
        shutil.copytree(application, destination, ignore=shutil.ignore_patterns("_build", ".mooncakes", "__pycache__", "moon.pkg"))
        manifest = ('import {\n' + ''.join('  ' + json.dumps(name) + ',\n' for name in config["imports"]) + '}\n\n') if config["imports"] else ''
        manifest += ('pkgtype(kind: "executable")\n\noptions(\n'
                     '  "native-stub": ' + json.dumps(config["stubs"]) + ',\n'
                     '  link: ' + json.dumps({"native": native}, indent=2) + ',\n)\n')
        (destination / "moon.pkg").write_text(manifest, encoding="utf-8")
        run([moon, "update"], destination)
        run([moon, "build", "--target", "native", "--deny-warn", "."], destination)
        evidence.update({"built": True, "application": str(destination), "native": native})
        if args.run:
            output = run([moon, "run", "--target", "native", "--deny-warn", "."], destination)
            evidence["output"] = output
            print(output, flush=True)
        print(f"Built application: {destination}", flush=True)
        return 0
    finally:
        report.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Evidence: {report}", flush=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error))
