"""Common build glue for the independent native FFI examples."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def run(command, directory, expected_status=0):
    result = subprocess.run(
        command, cwd=directory, text=True, encoding="utf-8", errors="replace",
        capture_output=True, check=False
    )
    if result.returncode != expected_status:
        raise RuntimeError(
            f"Command returned {result.returncode}, expected {expected_status}: "
            f"{shlex.join(command)}\n{result.stdout}{result.stderr}"
        )
    return result.stdout.strip()


def library_mapping(value):
    name, separator, filename = value.partition("=")
    if not separator or not re.fullmatch(r"[A-Za-z0-9_+][A-Za-z0-9_+.-]*", name) or not re.fullmatch(
        r"[A-Za-z0-9_+][A-Za-z0-9_+.-]*\.lib", filename
    ):
        raise argparse.ArgumentTypeError("expected NAME=FILE.lib (a library filename, without directories)")
    return name, filename


def arguments(description, allow_windows=False):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument(
        "--pc-dir", type=Path, required=True,
        help="directory containing the root library's installed .pc file",
    )
    parser.add_argument(
        "--path", type=Path, action="append", default=[],
        help="additional dependency search directory; may be repeated",
    )
    parser.add_argument("--moon", default="moon", help="MoonBit CLI executable")
    parser.add_argument("--cc", help="C compiler executable; defaults to cc on POSIX, MoonBit's MSVC discovery on Windows")
    parser.add_argument(
        "--msvc-lib", action="append", type=library_mapping, default=[],
        help="explicit -lNAME to FILE.lib mapping on Windows; may be repeated",
    )
    args = parser.parse_args()
    if os.name == "nt" and not allow_windows:
        parser.error("these examples require a POSIX native toolchain (Linux or macOS)")
    moon = shutil.which(args.moon)
    compiler_name = args.cc or (None if os.name == "nt" else "cc")
    compiler = shutil.which(compiler_name) if compiler_name else None
    if moon is None or (compiler_name and compiler is None):
        parser.error("MoonBit and the selected C compiler must be installed")
    if os.name == "nt" and compiler and Path(compiler).stem.lower() not in ("cl", "clang-cl"):
        parser.error("Windows examples require cl or clang-cl with the Windows SDK")
    if os.name != "nt" and args.msvc_lib:
        parser.error("--msvc-lib is only supported on Windows")
    mappings = {}
    for name, filename in args.msvc_lib:
        if name in mappings:
            parser.error(f"duplicate --msvc-lib mapping for {name}")
        mappings[name] = filename
    directories = [path.resolve() for path in [args.pc_dir, *args.path]]
    if not all(path.is_dir() for path in directories):
        parser.error("every explicit pkg-config search directory must exist")
    return moon, compiler, directories, mappings


def query_command(moon, directories, package, mode, static=False):
    command = [
        moon, "run", "--target", "native", "cmd/query",
        str(directories[0]), package, mode,
    ]
    for directory in directories[1:]:
        command.extend(["--path", str(directory)])
    if mode in ("--cflags", "--libs"):
        command.append("--json")
    if static:
        command.append("--static")
    return command


def query(moon, directories, package, mode, static=False):
    output = run(query_command(moon, directories, package, mode, static), ROOT)
    if mode not in ("--cflags", "--libs"):
        return output
    result = json.loads(output)
    if result["diagnostics"]:
        raise RuntimeError(f"{package} metadata has diagnostics: {result['diagnostics']}")
    return result["flags"]


def values(flags):
    return [flag["value"] for flag in flags]


def temporary_directory(prefix):
    temporary_root = ROOT / ".tmp"
    temporary_root.mkdir(exist_ok=True)
    return tempfile.TemporaryDirectory(prefix=prefix, dir=temporary_root)


def msvc_flags(flags, prefixes, library_names=None):
    """Translate only understood metadata options; never guess at opaque flags."""
    translated = []
    index = 0
    while index < len(flags):
        flag = flags[index]
        value = flag["value"]
        prefix = next((item for item in prefixes if value.startswith(item)), None)
        if prefix is None:
            raise RuntimeError(
                f"unsupported MSVC metadata flag {value!r} from "
                f"{flag['package']}:{flag['field']}; provide compatible metadata"
            )
        operand = value[len(prefix):]
        if not operand:
            index += 1
            if index >= len(flags) or any(
                flags[index][key] != flag[key] for key in ("package", "field", "location")
            ) or not flags[index]["value"] or flags[index]["value"].startswith("-"):
                raise RuntimeError(f"missing operand for MSVC metadata flag {value!r}")
            operand = flags[index]["value"]
        if prefix == "-l":
            # A spelling such as -l:archive.a is not a portable library name.
            if not re.fullmatch(r"[A-Za-z0-9_+][A-Za-z0-9_+.-]*", operand):
                raise RuntimeError(f"unsupported MSVC library name {operand!r}")
            translated.append((library_names or {}).get(operand, operand + ".lib"))
        else:
            translated.append(prefixes[prefix] + operand)
        index += 1
    return translated


def build_example(moon, compiler, example, stub, cflags, libs, success, msvc_libs=None):
    with temporary_directory(example + "-") as name:
        consumer = Path(name)
        for filename in ("moon.mod", "main.mbt", stub):
            shutil.copyfile(ROOT / "examples" / example / filename, consumer / filename)
        # Native manifests store flag fragments as strings. Quote individual
        # JSON array elements; no metadata is evaluated by a shell.
        compile_flags = values(cflags)
        link_flags = values(libs)
        if os.name == "nt":
            compile_flags = msvc_flags(cflags, {"-I": "/I", "-D": "/D", "-U": "/U"})
            link_flags = msvc_flags(libs, {"-L": "/LIBPATH:", "-l": ""}, msvc_libs)
            compile_flags = ["/utf-8", "/MT", *compile_flags]
            if link_flags:
                link_flags.insert(0, "/link")
            print(f"MSVC compile arguments: {json.dumps(compile_flags)}")
            print(f"MSVC link arguments: {json.dumps(link_flags)}")
        # Moon parses manifest flag strings as shell words on both platforms.
        # The pinned CLI passes cc-link-flags through the compiler driver, so
        # MSVC linker options require an explicit /link separator here.
        native = {
            "cc-flags": shlex.join(compile_flags),
            "stub-cc-flags": shlex.join(compile_flags),
            "cc-link-flags": shlex.join(link_flags),
        }
        if compiler:
            native.update({"cc": compiler, "stub-cc": compiler})
        manifest = (
            'pkgtype(kind: "executable")\n\noptions(\n'
            f'  "native-stub": [ {json.dumps(stub)} ],\n'
            f'  link: {json.dumps({"native": native}, indent=2)},\n)\n'
        )
        (consumer / "moon.pkg").write_text(manifest, encoding="utf-8")
        command = [moon, "run", "--target", "native", "--deny-warn", "."]
        run([*command[:-1], "--build-only", "."], consumer)
        output = run(command, consumer)
        if output != success:
            raise RuntimeError(f"Unexpected FFI program output:\n{output}")
        print(output)
