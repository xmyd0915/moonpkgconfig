"""Check dependency ordering with pkgconf 3.0.7 and real one-pass static linking."""

import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path)
    parser.add_argument("--reference", default=os.environ.get("PKGCONF"))
    parser.add_argument("--cc", default=shutil.which("cc") or shutil.which("gcc"))
    parser.add_argument("--ar", default=shutil.which("ar"))
    parser.add_argument("--report", type=Path, default=ROOT / "_build/verification/link-order.json")
    args = parser.parse_args()
    reference = args.reference or str(ROOT / ".tools/pkgconf/extracted/PFiles64/pkgconf-3.0.7/pkgconf.exe")
    reference = shutil.which(reference) or str(Path(reference).resolve())
    if not args.cc or not args.ar:
        parser.error("A GNU-compatible C compiler and ar are required")
    report = {"passed": False, "reference": "pkgconf 3.0.7", "cases": []}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    temporary = ROOT / ".tmp"
    temporary.mkdir(exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix="link-order-", dir=temporary)).resolve()
    report["workspace"] = str(workspace)

    def run(command, expected=0, env=None):
        result = subprocess.run(list(map(str, command)), cwd=workspace, env=env,
                                capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
        if result.returncode != expected:
            raise AssertionError(f"Expected {expected}, got {result.returncode}: {command}\n{result.stdout}{result.stderr}")
        return result

    try:
        if run([reference, "--version"]).stdout.strip() != "3.0.7":
            raise AssertionError("The differential reference must be pkgconf 3.0.7")
        if args.cli:
            cli = args.cli.resolve()
        else:
            moon = shutil.which("moon")
            if not moon:
                raise RuntimeError("MoonBit CLI is required")
            target = workspace / "target"
            result = subprocess.run([moon, "build", "--target", "native", "--release", "--target-dir", str(target),
                                     "cmd/moonpkgconfig"], cwd=ROOT, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace", timeout=180)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            directory = target / "native/release/build/cmd/moonpkgconfig"
            candidates = [directory / name for name in ("moonpkgconfig", "moonpkgconfig.exe")
                          if (directory / name).is_file()]
            if len(candidates) != 1:
                raise RuntimeError(f"Expected one CLI build artifact, found {candidates}")
            cli = candidates[0]
        report["compiler"] = run([args.cc, "--version"]).stdout.splitlines()[0]
        # Metadata may name a redundant direct dependency. Only the later branch
        # needs its symbol, so the old breadth-first order really fails to link.
        graphs = [
            ("triangle", {"app": ["base", "mid"], "mid": ["base"], "base": []},
             {"app": ["mid"], "mid": ["base"], "base": []}, ["app", "mid", "base"], ["app", "base", "mid"]),
            ("cross-layer", {"app": ["left", "right"], "left": ["base"], "right": ["bridge"], "bridge": ["base"], "base": []},
             {"app": ["left", "right"], "left": [], "right": ["bridge"], "bridge": ["base"], "base": []},
             ["app", "left", "right", "bridge", "base"], ["app", "left", "right", "base", "bridge"]),
        ]
        for label, dependencies, calls, expected_order, old_order in graphs:
            directory = workspace / label
            directory.mkdir()
            env = {k: v for k, v in os.environ.items() if not k.upper().startswith(("PKG_CONFIG_", "PKGCONF_"))}
            env.update(PKG_CONFIG_LIBDIR=str(directory), PKG_CONFIG_PATH="", PKG_CONFIG_SYSTEM_LIBRARY_PATH="")
            for name, required in dependencies.items():
                fields = "Requires: " + ", ".join(required) + "\n" if required else ""
                (directory / (name + ".pc")).write_text(
                    f"Name: {name}\nDescription: static link regression\nVersion: 1\n{fields}Libs: -l{name}\n", encoding="utf-8")
                source = "".join(f"int {dep}_value(void);\n" for dep in calls[name])
                source += f"int {name}_value(void) {{ return 1" + "".join(f" + {dep}_value()" for dep in calls[name]) + "; }\n"
                file = directory / (name + ".c")
                file.write_text(source, encoding="utf-8")
                obj = directory / (name + ".o")
                run([args.cc, "-c", file, "-o", obj])
                run([args.ar, "rcs", directory / ("lib" + name + ".a"), obj])
            def value(name):
                return 1 + sum(value(dep) for dep in calls[name])
            main_file = directory / "main.c"
            main_file.write_text(f"int app_value(void);\nint main(void) {{ return app_value() == {value('app')} ? 0 : 1; }}\n", encoding="utf-8")
            main_obj = directory / "main.o"
            run([args.cc, "-c", main_file, "-o", main_obj])
            actual = run([cli, "query", directory, "app", "--libs", "--static", "--json"])
            data = json.loads(actual.stdout)
            expected = ["-l" + name for name in expected_order]
            flags = [flag["value"] for flag in data["flags"]]
            reference_flags = shlex.split(run([reference, "--libs", "--static", "app"], env=env).stdout)
            if data["diagnostics"] or flags != expected or reference_flags != expected:
                raise AssertionError(f"{label}: expected {expected}, got {flags}, reference {reference_flags}")
            for origin, arguments in (("moonpkgconfig", flags), ("pkgconf", reference_flags)):
                binary = directory / (origin + (".exe" if os.name == "nt" else ".out"))
                run([args.cc, main_obj, "-L" + str(directory), *arguments, "-o", binary])
                run([binary])
            negative = subprocess.run([args.cc, str(main_obj), "-L" + str(directory),
                                       *["-l" + name for name in old_order], "-o", str(directory / "wrong-order.out")],
                                      capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
            if negative.returncode == 0 or "base_value" not in negative.stderr:
                raise AssertionError("The one-pass link negative control did not expose the old ordering defect")
            report["cases"].append({"case": label, "flags": flags, "reference_flags": reference_flags,
                                    "linked_and_ran": True, "old_order_rejected": True,
                                    "negative_exit": negative.returncode, "negative_stderr": negative.stderr})
        report["passed"] = True
    except (OSError, ValueError, AssertionError, RuntimeError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
        raise
    finally:
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Static link ordering: {len(report['cases'])} graphs linked and ran; old orders rejected; {args.report}")


if __name__ == "__main__":
    main()
