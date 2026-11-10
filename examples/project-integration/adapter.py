"""Shared configuration and strict flag translation for the experimental hook."""

import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess

ROOT = Path(__file__).resolve().parent
DEPENDENCY = "xmyd0915/moonpkgconfig@0.3.1"
NAME = r"[A-Za-z0-9_+][A-Za-z0-9_+.-]*"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def planner_sources():
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted((ROOT / "planner").rglob("*"))
            if path.is_file() and not any(part in ("_build", ".mooncakes")
                                          for part in path.relative_to(ROOT / "planner").parts)}


def run(command, directory, allowed=(0,)):
    result = subprocess.run(command, cwd=directory, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=180)
    if result.returncode not in allowed:
        raise RuntimeError(f"Command failed ({result.returncode}): {shlex.join(command)}\n"
                           f"{result.stdout}{result.stderr}")
    return result


def read_bindings(project):
    data = json.loads((project / "native-packages.json").read_text(encoding="utf-8"))
    if not isinstance(data, dict) or set(data) != {"bindings"} or not isinstance(data["bindings"], list) or not data["bindings"]:
        raise ValueError("native-packages.json requires a nonempty bindings array")
    packages, variables = set(), set()
    for item in data["bindings"]:
        if not isinstance(item, dict) or set(item) != {"package", "pc", "variable", "static"}:
            raise ValueError("Each binding requires package, pc, variable and static")
        if (not isinstance(item["package"], str) or not re.fullmatch(r"[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+)+", item["package"])
                or not isinstance(item["pc"], str) or not re.fullmatch(NAME, item["pc"])
                or not isinstance(item["variable"], str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", item["variable"])
                or type(item["static"]) is not bool):
            raise ValueError("Invalid package, pc, variable or static binding")
        if item["package"] in packages or item["variable"] in variables or item["variable"] == "PC_RUNTIME":
            raise ValueError("Package and variable bindings must be unique")
        packages.add(item["package"])
        variables.add(item["variable"])
    return data["bindings"]


def arguments(flags, compiling, mappings):
    """Preserve order, duplicates and operand origins; reject opaque options."""
    prefixes = ("-I", "-D", "-U") if compiling else ("-L", "-l")
    values = []
    i = 0
    while i < len(flags):
        flag = flags[i]
        value = flag["value"]
        prefix = value[:2]
        if prefix not in prefixes:
            raise ValueError(f"Unsupported native option {value!r} from {flag['package']}:{flag['field']}")
        operand = value[2:]
        if not operand:
            i += 1
            if i == len(flags) or any(flags[i][key] != flag[key] for key in ("package", "field", "location")):
                raise ValueError(f"Missing or cross-origin operand for {prefix}")
            operand = flags[i]["value"]
        if not operand or operand.startswith("-") or any(c in operand for c in ("\x00", "\n", "\r")):
            raise ValueError(f"Invalid operand for {prefix}")
        if prefix == "-l" and not re.fullmatch(NAME, operand):
            raise ValueError(f"Unsupported library name {operand!r}")
        if os.name == "nt":
            value = mappings.get(operand, operand + ".lib") if prefix == "-l" else {
                "-I": "/I", "-D": "/D", "-U": "/U", "-L": "/LIBPATH:",
            }[prefix] + operand
        else:
            value = prefix + operand
        values.append(value)
        i += 1
    return values


def plan(project, configured):
    executable = Path(configured["planner"])
    if configured["dependency"] != DEPENDENCY or configured["planner_sources"] != planner_sources() or digest(executable) != configured["planner_sha256"]:
        raise ValueError("Planner changed; run configure.py again")
    output = {"vars": {"PC_RUNTIME": "/utf-8 /MT" if os.name == "nt" else ""}, "link_configs": []}
    evidence = []
    for binding in read_bindings(project):
        result = run([str(executable), binding["pc"], "static" if binding["static"] else "dynamic",
                      *configured["pc_directories"]], project, (0, 1))
        data = json.loads(result.stdout)
        problems = []
        for section in ("cflags", "libs"):
            for problem in data[section]["diagnostics"]:
                if problem not in problems:
                    problems.append(problem)
        if problems or result.returncode:
            lines = []
            for problem in problems:
                at = problem["location"]
                lines.append(f"{problem['code']} {at['source']}:{at['line']}:{at['column']} {problem['message']}")
            raise ValueError("\n".join(lines) or "Planner failed without diagnostics")
        cflags = arguments(data["cflags"]["flags"], True, configured["msvc_libraries"])
        libs = arguments(data["libs"]["flags"], False, configured["msvc_libraries"])
        output["vars"][binding["variable"]] = shlex.join(cflags)
        # One ordered string avoids the reordering caused by splitting -L/-l
        # into separate hook fields. Moon supplies MSVC's /link delimiter.
        output["link_configs"].append({"package": binding["package"], "link_flags": shlex.join(libs)})
        evidence.append({"binding": binding, "plan": data, "compile_arguments": cflags, "link_arguments": libs})
    return output, evidence
