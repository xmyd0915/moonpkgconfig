"""Verify pinned templates, independent query expectations and seeded inputs."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import shlex
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "testdata/real-world"


def run(command, **kwargs):
    return subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                          errors="strict", capture_output=True, timeout=20, **kwargs)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def build(moon, name):
    result = run([moon, "build", "--target", "native", "--release", "cmd/" + name])
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    directory = ROOT / "_build/native/release/build/cmd" / name
    binary = next((directory / file for file in [name + ".exe", name]
                   if (directory / file).is_file()), None)
    if binary is None:
        raise AssertionError("Missing executable: " + name)
    return str(binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", default=os.environ.get("PKGCONF"))
    parser.add_argument("--no-reference", action="store_true",
                        help="Run declared expectations and robustness only")
    parser.add_argument("--seed", type=int, default=20261017)
    parser.add_argument("--random-cases", type=int, default=64)
    args = parser.parse_args()
    if args.random_cases < 1:
        parser.error("--random-cases must be positive")
    moon = shutil.which("moon")
    if moon is None:
        parser.error("MoonBit CLI must be installed")
    reference = None
    if not args.no_reference:
        local = ROOT / ".tools/pkgconf/extracted/PFiles64/pkgconf-3.0.7/pkgconf.exe"
        reference = args.reference or (str(local) if local.is_file() else shutil.which("pkgconf"))
        if reference is None:
            parser.error("pkgconf 3.0.7 is required; pass --reference or --no-reference")
        version = run([reference, "--version"])
        if version.returncode or version.stdout.strip() != "3.0.7":
            parser.error("The differential reference must be pkgconf 3.0.7")

    temporary = ROOT / ".tmp"
    temporary.mkdir(exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix="compatibility-", dir=temporary))
    output = ROOT / "_build/verification/compatibility.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {"schema": 1, "seed": args.seed, "random_cases": args.random_cases,
              "reference": "pkgconf 3.0.7" if reference else None,
              "moon_version": run([moon, "version", "--all"]).stdout.strip(),
              "inputs": str(workspace), "corpus_queries": 0, "reference_queries": 0,
              "static_order_queries": 0, "generated_valid": 0, "mutated_inputs": 0,
              "cases": [], "passed": False}

    def record(path, category, options=()):
        report["current_case"] = {"file": str(path.relative_to(workspace)),
                                  "sha256": digest(path.read_bytes()),
                                  "category": category, "options": list(options)}

    def validate(result, key):
        if result.returncode not in (0, 1):
            raise AssertionError(f"Unexpected exit {result.returncode}: {result.stdout[:4096]} {result.stderr[:4096]}")
        data = json.loads(result.stdout)
        if not isinstance(data.get(key), list) or not isinstance(data.get("diagnostics"), list):
            raise AssertionError("JSON result schema changed")
        if bool(data["diagnostics"]) != (result.returncode == 1):
            raise AssertionError("Exit status disagrees with diagnostics")
        for item in data[key] + data["diagnostics"]:
            at = item["location"]
            if not at["source"] or at["line"] < 1 or at["column"] < 1:
                raise AssertionError("Missing or invalid source location")
        return data

    try:
        query = build(moon, "query")
        inspect = build(moon, "inspect")
        manifest = json.loads((CORPUS / "corpus.json").read_text(encoding="utf-8"))
        packages = {item["package"]: item for item in manifest["packages"]}
        configured = workspace / "configured"
        configured.mkdir()
        texts = {}
        for package, item in packages.items():
            for file_key, hash_key in [("file", "sha256"), ("license", "license_sha256")]:
                if digest((CORPUS / item[file_key]).read_bytes()) != item[hash_key]:
                    raise AssertionError("Upstream bytes changed: " + item[file_key])
            prefix = "/opt/moonpkgconfig-corpus/" + package
            item["prefix"] = prefix
            substitutions = {"prefix": prefix, "exec_prefix": "${prefix}",
                             "libdir": "${exec_prefix}/lib", "includedir": "${prefix}/include",
                             "sharedlibdir": "${exec_prefix}/shared", "toolexeclibdir": "${libdir}",
                             **item["substitutions"]}
            template = (CORPUS / item["file"]).read_text(encoding="utf-8")
            text = re.sub(r"@([A-Za-z0-9_]+)@", lambda m: substitutions[m[1]], template)
            path = configured / (package + ".pc")
            path.write_bytes(text.encode("utf-8"))
            texts[package] = text
        report["sources"] = manifest["packages"]

        def expected_flags(package, field, static):
            item = packages[package]
            flags = [(value.format(prefix=item["prefix"]), package, field)
                     for value in item.get(field.lower(), [])]
            if static:
                flags += [(value.format(prefix=item["prefix"]), package, field + ".private")
                          for value in item.get("private_" + field.lower(), [])]
            if field == "Cflags" or static:
                for dependency in item.get("private_requires", []):
                    flags += expected_flags(dependency, field, static)
            return sorted(flags, key=lambda flag: flag[2].endswith(".private")) if field == "Cflags" else flags

        reference_env = {key: value for key, value in os.environ.items()
                         if not key.upper().startswith("PKG_CONFIG_") and not key.upper().startswith("PKGCONF_")}
        reference_env.update({"PKG_CONFIG_PATH": str(configured), "PKG_CONFIG_LIBDIR": str(configured),
                              "PKG_CONFIG_SYSTEM_INCLUDE_PATH": "", "PKG_CONFIG_SYSTEM_LIBRARY_PATH": ""})
        modes = [("--cflags", "Cflags", None), ("--cflags-only-I", "Cflags", "-I"),
                 ("--cflags-only-other", "Cflags", "other"), ("--libs", "Libs", None),
                 ("--libs-only-L", "Libs", "-L"), ("--libs-only-l", "Libs", "-l"),
                 ("--libs-only-other", "Libs", "other")]
        for package, item in packages.items():
            for static in [False, True]:
                for mode, field, selection in modes:
                    options = [mode] + (["--static"] if static else [])
                    path = configured / (package + ".pc")
                    record(path, "corpus", options)
                    expected = expected_flags(package, field, static)
                    if selection == "other":
                        prefixes = ("-I",) if field == "Cflags" else ("-L", "-l")
                        expected = [flag for flag in expected if not flag[0].startswith(prefixes)]
                    elif selection:
                        expected = [flag for flag in expected if flag[0].startswith(selection)]
                    data = validate(run([query, str(configured), package, *options, "--json"]), "flags")
                    actual = [(flag["value"], flag["package"], flag["field"]) for flag in data["flags"]]
                    if data["diagnostics"] or actual != expected:
                        raise AssertionError(f"{package} {options}: expected {expected}, got {data}")
                    for flag in data["flags"]:
                        source = configured / (flag["package"] + ".pc")
                        line = texts[flag["package"]].splitlines()[flag["location"]["line"] - 1]
                        if Path(flag["location"]["source"]) != source or not line.startswith(flag["field"] + ":"):
                            raise AssertionError("Flag origin no longer points to its declaring field")
                    values = [flag[0] for flag in expected]
                    if reference:
                        other = run([reference, *options, package], env=reference_env)
                        if other.returncode or shlex.split(other.stdout) != values:
                            raise AssertionError(f"pkgconf differs: {other.stdout!r} {other.stderr!r}; expected {values}")
                        report["reference_queries"] += 1
                    report["corpus_queries"] += 1
                    report["cases"].append(dict(report["current_case"], expected=values))
            for options, expected_text, status in [
                (["--modversion"], item["version"], 0),
                (["--variable=prefix"], item["prefix"], 0),
                (["--variable=prefix", "--define-variable=prefix=/custom"], "/custom", 0),
                (["--exists"], "", 0),
                (["--atleast-version=" + item["version"]], "", 0),
                (["--exact-version=999.0"], "", 1),
            ]:
                record(configured / (package + ".pc"), "corpus", options)
                actual = run([query, str(configured), package, *options])
                if actual.returncode != status or actual.stdout.strip() != expected_text:
                    raise AssertionError("Metadata query differs: " + actual.stdout + actual.stderr)
                if reference:
                    other = run([reference, *options, package], env=reference_env)
                    if other.returncode != status or other.stdout.strip() != expected_text:
                        raise AssertionError("pkgconf metadata differs: " + other.stdout + other.stderr)
                    report["reference_queries"] += 1
                report["corpus_queries"] += 1
                report["cases"].append(dict(report["current_case"], expected=expected_text, status=status))

        ordered = workspace / "static-order"
        ordered.mkdir()
        for package, dependency in [("app", "helper"), ("helper", "")]:
            text = (f"Name: {package}\nDescription: static order\nVersion: 1\n"
                    f"Requires.private: {dependency}\nCflags: -I/{package}\n"
                    f"Cflags.private: -D{package}_STATIC\n")
            (ordered / (package + ".pc")).write_bytes(text.encode("utf-8"))
        order_env = dict(reference_env, PKG_CONFIG_PATH=str(ordered), PKG_CONFIG_LIBDIR=str(ordered))
        for options, expected in [
            (["--cflags"], ["-I/app", "-I/helper"]),
            (["--cflags", "--static"], ["-I/app", "-I/helper", "-Dapp_STATIC", "-Dhelper_STATIC"]),
            (["--cflags-only-I", "--static"], ["-I/app", "-I/helper"]),
            (["--cflags-only-other", "--static"], ["-Dapp_STATIC", "-Dhelper_STATIC"]),
        ]:
            record(ordered / "app.pc", "static-order", options)
            data = validate(run([query, str(ordered), "app", *options, "--json"]), "flags")
            if data["diagnostics"] or [flag["value"] for flag in data["flags"]] != expected:
                raise AssertionError("Static compiler field order differs: " + str(data))
            if reference:
                other = run([reference, *options, "app"], env=order_env)
                if other.returncode or shlex.split(other.stdout) != expected:
                    raise AssertionError("pkgconf static compiler field order differs")
                report["reference_queries"] += 1
            report["static_order_queries"] += 1
            report["cases"].append(dict(report["current_case"], expected=expected))

        rng = random.Random(args.seed)
        generated = workspace / "generated"
        generated.mkdir()
        path = generated / "case.pc"
        header = "Name: case\nDescription: generated boundary check\nVersion: 1\n"
        alphabet = "ab09 /\\\"'$`{}[]()*?;:=+-_喵é😀"
        for index in range(args.random_cases):
            tokens = ["".join(rng.choice(alphabet) for _ in range(rng.randrange(25)))
                      for _ in range(rng.randrange(1, 10))]
            fragment = shlex.join(tokens)
            expected = shlex.split(fragment)
            # .pc substitution runs before shell-fragment tokenization.
            raw = fragment.replace("$", "$$")
            newline = "\r\n" if index % 3 == 0 else "\n"
            text = (header + "Cflags: " + raw + "\n").replace("\n", newline)
            if index % 3 == 1:
                text = "\ufeff" + text
            if index % 3 == 2:
                text = text.rstrip("\n")
            path.write_bytes(text.encode("utf-8"))
            record(path, "generated-valid", ["--cflags"])
            result = run([query, str(generated), "case", "--cflags", "--json"])
            data = validate(result, "flags")
            if data["diagnostics"] or [flag["value"] for flag in data["flags"]] != expected:
                raise AssertionError(f"Fragment disagrees with Python shlex: {tokens!r}; {data}")
            rendered = run([query, str(generated), "case", "--cflags"])
            if rendered.returncode or shlex.split(rendered.stdout) != expected:
                raise AssertionError("Shell rendering lost token boundaries")
            saved = generated / f"valid-{index:04}.txt"
            saved.write_bytes(path.read_bytes())
            report["cases"].append(dict(report["current_case"], index=index,
                                        file=str(saved.relative_to(workspace))))
            report["generated_valid"] += 1

        mutations = [(package + "-truncated-" + str(cut), text[:cut])
                     for package, text in texts.items() for cut in [0, len(text) // 2, len(text) - 1]]
        mutations += [("syntax-" + str(index), header + fragment) for index, fragment in enumerate([
            "Cflags: 'unfinished", "Cflags: trailing\\", "Requires: missing >=",
            "Requires: missing == 1", "Requires: missing", "Requires: case",
            "Conflicts: case", "Cflags: ${missing}", "Cflags: ${unclosed",
            "prefix=${prefix}", "Name: duplicate", "pcfiledir=/reserved",
        ])]
        noise_alphabet = alphabet + "\n\r\t#\0\ufeff<>"
        mutations += [("noise-" + str(index), header + "".join(rng.choice(noise_alphabet)
                       for _ in range(rng.randrange(2048)))) for index in range(args.random_cases)]
        for index, (label, text) in enumerate(mutations):
            path.write_bytes(text.encode("utf-8"))
            record(path, label)
            validate(run([inspect, str(path), "--json"]), "entries")
            command = [query, str(generated), "case", "--libs", "--static", "--json"]
            result = run(command)
            validate(result, "flags")
            validate(run([query, str(generated), "case", "--cflags", "--static", "--json"]), "flags")
            if index % 10 == 0:
                repeated = run(command)
                if (repeated.returncode, repeated.stdout) != (result.returncode, result.stdout):
                    raise AssertionError("Repeated query was not deterministic")
            saved = generated / f"mutation-{index:04}.txt"
            saved.write_bytes(path.read_bytes())
            report["cases"].append(dict(report["current_case"], index=index,
                                        file=str(saved.relative_to(workspace))))
            report["mutated_inputs"] += 1
        report["passed"] = True
        report.pop("current_case", None)
    except Exception as error:
        report["failure"] = str(error)
        raise
    finally:
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("Compatibility evidence: " + str(output), flush=True)
    print(f"Compatibility: {report['corpus_queries']} corpus queries, "
          f"{report['static_order_queries']} static order queries, "
          f"{report['reference_queries']} pkgconf comparisons, "
          f"{report['generated_valid']} generated valid inputs, "
          f"{report['mutated_inputs']} malformed/truncated inputs passed (seed {args.seed})")


if __name__ == "__main__":
    main()
