"""Compare an explicit installed .pc corpus with pkgconf 3.0.7.

No packages are silently skipped. The report describes only the supplied
directories, not every package installed on the machine. --self-test exercises
the Python harness without MoonBit, pkgconf, or a system package installation.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
PACKAGE = r"[A-Za-z0-9_+][A-Za-z0-9_+.-]*"
REQUIREMENT = re.compile(r"(" + PACKAGE + r")(?:\s*(>=|<=|=|>|<)\s*(\S+))?")
REFERENCE_OPTIONS = ["--no-uninstalled", "--dont-define-prefix", "--dont-relocate-paths",
                     "--maximum-traverse-depth=-1", "--keep-system-cflags", "--keep-system-libs"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean_environment(directories):
    env = {key: value for key, value in os.environ.items()
           if not key.upper().startswith(("PKG_CONFIG_", "PKGCONF_"))}
    env.update(PKG_CONFIG_PATH="", PKG_CONFIG_LIBDIR=os.pathsep.join(map(str, directories)),
               PKG_CONFIG_SYSTEM_INCLUDE_PATH="", PKG_CONFIG_SYSTEM_LIBRARY_PATH="")
    return env


def inventory(directories):
    selected, files = {}, []
    for directory in directories:
        if not directory.is_dir():
            raise ValueError(f"Metadata directory does not exist: {directory}")
        for path in sorted(directory.iterdir(), key=lambda item: item.name):
            if not path.name.endswith(".pc"):
                continue
            name = path.name[:-3]
            if not re.fullmatch(PACKAGE, name):
                raise ValueError(f"Unsupported filename-derived package identifier: {path}")
            if not path.is_file():
                raise ValueError(f"Metadata entry is not a readable regular file: {path}")
            data = path.read_bytes()
            # A non-UTF-8 corpus is outside the CLI's input contract, not a pass.
            data.decode("utf-8", errors="strict")
            files.append({"id": name, "path": str(path), "resolved_path": str(path.resolve()),
                          "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                          "selected": name not in selected})
            selected.setdefault(name, path)
    if not selected:
        raise ValueError("The explicit directories contain no .pc files")
    return selected, files


def requirements(text):
    result = []
    for line in text.splitlines():
        if not line.strip():
            continue
        match = REQUIREMENT.fullmatch(line.strip())
        if not match:
            raise ValueError(f"Unsupported pkgconf dependency expression: {line!r}")
        name, operator, version = match.groups()
        result.append((name, name if operator is None else f"{name} {operator} {version}"))
    return result


def provider_id(name, text, selected):
    paths = [Path(line).resolve() for line in text.splitlines() if line.strip()]
    if len(paths) != 1:
        raise ValueError(f"Expected one selected metadata path for dependency {name!r}: {text!r}")
    path = paths[0]
    if name in selected:
        if selected[name].resolve() != path:
            raise ValueError(f"Reference search precedence differs for {name!r}: {path}")
        return name
    matches = [candidate for candidate, source in selected.items() if source.resolve() == path]
    if len(matches) != 1:
        raise ValueError(f"Virtual dependency {name!r} has an ambiguous or out-of-corpus provider: {path}")
    return matches[0]


def check_order(flags, graph, root):
    positions = {}
    for index, flag in enumerate(flags):
        name = flag["package"]
        if name not in graph:
            raise ValueError(f"Flag origin {name!r} is outside the reference closure for {root!r}")
        positions.setdefault(name, index)
    checked, violations = 0, []
    for dependant, position in positions.items():
        pending, seen = list(graph[dependant]), set()
        while pending:
            dependency = pending.pop()
            if dependency in seen:
                continue
            seen.add(dependency)
            if dependency == dependant:
                raise ValueError(f"Reference dependency graph contains a cycle at {dependant!r}")
            if dependency in positions:
                checked += 1
                if position >= positions[dependency]:
                    violations.append([dependant, dependency])
            pending.extend(graph[dependency])
    if violations:
        raise AssertionError(f"Dependants follow their dependencies: {violations}")
    return {"first_positions": positions, "checked_relations": checked,
            "packages_without_flags": sorted(set(graph) - set(positions))}


class Corpus:
    def __init__(self, selected, reference):
        self.selected = selected
        self.reference = reference
        self.edges = {}
        self.providers = {}

    def closure(self, root, private):
        graph, pending = {}, [root]
        while pending:
            name = pending.pop()
            if name in graph:
                continue
            key = (name, private)
            if key not in self.edges:
                dependencies = []
                options = ["--print-requires"] + (["--print-requires-private"] if private else [])
                for option in options:
                    data = self.reference([option, name], allowed=(0,))
                    for requested, expression in requirements(data.stdout):
                        if expression not in self.providers:
                            path = self.reference(["--path", expression], allowed=(0,)).stdout
                            self.providers[expression] = provider_id(requested, path, self.selected)
                        target = self.providers[expression]
                        if target not in dependencies:
                            dependencies.append(target)
                self.edges[key] = dependencies
            graph[name] = self.edges[key]
            pending.extend(graph[name])
        return graph


def execute(command, cwd, env, timeout, allowed=(0,)):
    result = subprocess.run(list(map(str, command)), cwd=cwd, env=env, capture_output=True,
                            text=True, encoding="utf-8", errors="strict", timeout=timeout)
    if result.returncode not in allowed:
        raise RuntimeError(f"Unexpected exit {result.returncode}: {command}\n{result.stdout}{result.stderr}")
    return result


def query_report(result):
    data = json.loads(result.stdout)
    if (data.get("schema_version") != 1 or data.get("command") != "query"
            or not isinstance(data.get("flags"), list) or not isinstance(data.get("diagnostics"), list)):
        raise ValueError("CLI did not return a supported query JSON report")
    valid = {0: {"ok"}, 1: {"diagnostics", "nonmatch"}}
    if data.get("status") not in valid[result.returncode] or data.get("error") is not None:
        raise ValueError(f"CLI status does not match its exit code: {data}")
    if bool(data["diagnostics"]) != (data["status"] == "diagnostics"):
        raise ValueError("CLI diagnostic status does not match its diagnostic payload")
    for flag in data["flags"]:
        if not isinstance(flag.get("value"), str) or not isinstance(flag.get("package"), str):
            raise ValueError("CLI returned a flag without its argument or package origin")
    return data


def prepare_cli(args, workspace, env, report):
    if args.cli:
        cli = args.cli.resolve()
        if not cli.is_file():
            raise ValueError(f"CLI executable not found: {cli}")
        report["toolchain"] = None
        report["toolchain_provenance"] = "Unknown for the supplied executable; only its SHA-256 is established"
    else:
        found = shutil.which(args.moon)
        if not found:
            raise ValueError("MoonBit CLI is required unless --cli is supplied")
        moon = Path(found).resolve()
        moonc = moon.parent / ("moonc.exe" if os.name == "nt" else "moonc")
        build_env = {key: value for key, value in env.items() if not key.upper().startswith("MOON")}
        build_env.update(MOON_HOME=str(moon.parent.parent), MOONC_OVERRIDE=str(moonc),
                         PATH=str(moon.parent) + os.pathsep + env.get("PATH", ""))
        report["toolchain"] = {
            "moon": execute([moon, "version"], ROOT, build_env, args.timeout).stdout.strip(),
            "moonc": execute([moonc, "-v"], ROOT, build_env, args.timeout).stdout.strip(),
        }
        target = workspace / "target"
        execute([moon, "build", "--target", "native", "--release", "--deny-warn",
                 "--target-dir", target, "cmd/moonpkgconfig"], ROOT, build_env, max(180, args.timeout))
        directory = target / "native/release/build/cmd/moonpkgconfig"
        candidates = [directory / name for name in ("moonpkgconfig", "moonpkgconfig.exe")
                      if (directory / name).is_file()]
        if len(candidates) != 1:
            raise ValueError(f"Expected one compiled CLI executable, found {candidates}")
        cli = candidates[0]
    report["cli"] = {"path": str(cli), "sha256": digest(cli)}
    return cli


def verify(args, report, checkpoint=None):
    directories = [path.resolve() for path in args.directory]
    selected, files = inventory(directories)
    roots = sorted(selected) if not args.package else list(dict.fromkeys(args.package))
    missing = sorted(set(roots) - set(selected))
    if missing:
        raise ValueError(f"Requested roots are not filename identifiers in the explicit corpus: {missing}")
    report.update({"directories": list(map(str, directories)), "files": files, "packages": roots,
                   "selected_package_count": len(selected), "root_count": len(roots),
                   "scope": "all explicit-directory package ids" if not args.package else "explicit roots and their reference dependency closures"})
    env = clean_environment(directories)
    reference = shutil.which(args.reference)
    if not reference:
        raise ValueError(f"pkgconf reference executable not found: {args.reference}")
    version = execute([reference, "--version"], ROOT, env, args.timeout).stdout.strip()
    if version != "3.0.7":
        raise ValueError(f"Expected pkgconf 3.0.7, found {version!r}")
    report["reference"] = {"path": str(Path(reference).resolve()), "version": version,
                           "sha256": digest(Path(reference)), "options": REFERENCE_OPTIONS}

    metadata_cache = {}
    def reference_query(arguments, allowed=(0, 1)):
        key = tuple(arguments)
        cacheable = arguments[0] in ("--print-requires", "--print-requires-private", "--path")
        if cacheable and key in metadata_cache:
            return metadata_cache[key]
        result = execute([reference, *REFERENCE_OPTIONS, *arguments], ROOT, env, args.timeout, allowed)
        if cacheable:
            metadata_cache[key] = result
        return result

    temporary = ROOT / ".tmp"
    temporary.mkdir(exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix="system-packages-", dir=temporary)).resolve()
    cli = prepare_cli(args, workspace, env, report)
    report["reference_selected_paths"] = {}
    corpus = Corpus(selected, reference_query)
    base = [cli, "query", directories[0]]
    extra = [item for directory in directories[1:] for item in ("--path", directory)]

    def case(name, mode, static=False):
        record = {"package": name, "mode": mode, "static": static, "passed": False}
        report["cases"].append(record)
        try:
            options = [mode] + (["--static"] if static else [])
            ref = reference_query([*options, name])
            actual = execute([*base, name, *extra, *options, "--json"], ROOT, env, args.timeout, (0, 1))
            data = query_report(actual)
            record.update({"reference_exit": ref.returncode, "cli_exit": actual.returncode,
                           "cli_status": data["status"]})
            if data["diagnostics"]:
                record["diagnostics"] = data["diagnostics"]
            if ref.returncode != actual.returncode:
                raise AssertionError(f"Exit codes differ; reference stderr: {ref.stderr}; CLI diagnostics: {data['diagnostics']}")
            if mode in ("--libs", "--cflags"):
                if ref.returncode == 0:
                    expected = sorted(set(shlex.split(ref.stdout)))
                    returned = sorted({flag["value"] for flag in data["flags"]})
                    record.update(reference_flags=expected, flags=returned, arguments_compared=True)
                    if expected != returned:
                        raise AssertionError(f"Argument sets differ: missing={sorted(set(expected)-set(returned))}, extra={sorted(set(returned)-set(expected))}")
                    if mode == "--libs":
                        graph = corpus.closure(name, static)
                        record["dependency_graph"] = graph
                        record["order"] = check_order(data["flags"], graph, name)
                else:
                    if data["status"] != "diagnostics" or data["matched"] is not None:
                        raise AssertionError("Failed flag query must report unevaluated diagnostics")
                    record.update(arguments_compared=False, partial_flags=data["flags"],
                                  reference_partial_stdout=ref.stdout,
                                  comparison_note="Both queries failed; partial JSON flags are diagnostic evidence, not evaluated arguments")
            elif mode == "--modversion":
                record.update(reference_value=ref.stdout.strip(), value=data["value"])
                if ref.returncode == 0 and data["value"] != ref.stdout.strip():
                    raise AssertionError("Module versions differ")
            else:
                record["matched"] = data["matched"]
                if ref.returncode == 0 and data["matched"] is not True:
                    raise AssertionError("Successful predicate did not return matched=true")
                if actual.returncode == 1 and ((data["status"] == "nonmatch" and data["matched"] is not False)
                                             or (data["status"] == "diagnostics" and data["matched"] is not None)):
                    raise AssertionError("Failed predicate conflates nonmatch with unevaluated diagnostics")
            if ref.stderr or actual.stderr:
                record.update(reference_stderr=ref.stderr, cli_stderr=actual.stderr)
            record["passed"] = True
            return data
        except (OSError, ValueError, KeyError, TypeError, AssertionError, RuntimeError, subprocess.SubprocessError) as error:
            record["error"] = {"kind": type(error).__name__, "message": str(error)}
            if isinstance(error, subprocess.TimeoutExpired):
                raise
            return None

    for index, name in enumerate(roots, 1):
        try:
            path = reference_query(["--path", name], allowed=(0,)).stdout
            provider_id(name, path, selected)
            report["reference_selected_paths"][name] = path.strip()
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            report["cases"].append({"package": name, "mode": "source-selection", "passed": False,
                                    "error": {"kind": type(error).__name__, "message": str(error)}})
            if isinstance(error, subprocess.TimeoutExpired):
                raise
        version_data = case(name, "--modversion")
        case(name, "--cflags")
        case(name, "--libs")
        case(name, "--libs", static=True)
        case(name, "--exists")
        for mode in ("--atleast-version=", "--exact-version=", "--max-version="):
            for boundary in ("0", "999999999"):
                case(name, mode + boundary)
        if version_data is not None and version_data["status"] == "ok":
            case(name, "--exact-version=" + version_data["value"])
        if index % 25 == 0 or index == len(roots):
            print(f"System corpus: checked {index}/{len(roots)} explicit roots", flush=True)
            report["completed_roots"] = index
            if checkpoint:
                checkpoint()
    report["provider_mappings"] = corpus.providers
    report["reference_metadata_queries"] = len(metadata_cache)
    _, after = inventory(directories)
    report["metadata_unchanged"] = files == after
    if not report["metadata_unchanged"]:
        raise AssertionError("The metadata corpus changed while verification was running")
    report["cli_unchanged"] = digest(cli) == report["cli"]["sha256"]
    if not report["cli_unchanged"]:
        raise AssertionError("The CLI executable changed while verification was running")
    report["failed_cases"] = sum(not item["passed"] for item in report["cases"])
    report["passed"] = report["failed_cases"] == 0


def self_test():
    import unittest

    class HarnessTests(unittest.TestCase):
        def test_requirements_reject_unsupported_syntax(self):
            self.assertEqual(requirements("glib-2.0 >= 2.58\nzlib\n"),
                             [("glib-2.0", "glib-2.0 >= 2.58"), ("zlib", "zlib")])
            with self.assertRaises(ValueError):
                requirements("broken dependency expression")

        def test_search_precedence_and_virtual_provider(self):
            with tempfile.TemporaryDirectory() as temporary:
                first, second = Path(temporary) / "first", Path(temporary) / "second"
                first.mkdir()
                second.mkdir()
                for directory, text in ((first, "first"), (second, "second")):
                    (directory / "real.pc").write_text(text, encoding="utf-8")
                selected, files = inventory([first, second])
                self.assertEqual([item["selected"] for item in files], [True, False])
                self.assertEqual(provider_id("virtual", str(first / "real.pc"), selected), "real")
                with self.assertRaises(ValueError):
                    provider_id("real", str(second / "real.pc"), selected)

        def test_transitive_order_through_package_without_flags(self):
            graph = {"app": ["mid"], "mid": ["base"], "base": []}
            flags = [{"package": "app"}, {"package": "base"}]
            self.assertEqual(check_order(flags, graph, "app")["checked_relations"], 1)
            with self.assertRaises(AssertionError):
                check_order(list(reversed(flags)), graph, "app")
            with self.assertRaises(ValueError):
                check_order([{"package": "external"}], graph, "app")

        def test_closure_uses_actual_provider_and_private_edges(self):
            selected = {name: Path(name + ".pc").resolve() for name in ("app", "real", "hidden")}
            replies = {("--print-requires", "app"): "virtual >= 1\n",
                       ("--print-requires-private", "app"): "hidden\n",
                       ("--path", "virtual >= 1"): str(selected["real"]),
                       ("--path", "hidden"): str(selected["hidden"])}
            def reference(arguments, allowed):
                return subprocess.CompletedProcess(arguments, 0, replies.get(tuple(arguments), ""), "")
            corpus = Corpus(selected, reference)
            self.assertEqual(corpus.closure("app", False), {"app": ["real"], "real": []})
            self.assertEqual(set(corpus.closure("app", True)), {"app", "real", "hidden"})

        def test_failed_process_and_invalid_utf8_fail(self):
            import sys
            with self.assertRaises(RuntimeError):
                execute([sys.executable, "-c", "raise SystemExit(7)"], ROOT, os.environ.copy(), 5)
            with self.assertRaises(subprocess.TimeoutExpired):
                execute([sys.executable, "-c", "import time; time.sleep(2)"], ROOT, os.environ.copy(), 0.1)
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary)
                (path / "bad.pc").write_bytes(b"\xff")
                with self.assertRaises(UnicodeDecodeError):
                    inventory([path])

        def test_complete_harness_caches_edges_and_reports_mismatch(self):
            from unittest.mock import patch
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                (directory / "app.pc").write_text("Name: app\nDescription: test\nVersion: 2\n", encoding="utf-8")
                reference, cli = directory / "reference", directory / "cli"
                reference.write_bytes(b"fake reference")
                cli.write_bytes(b"fake cli")
                args = argparse.Namespace(directory=[directory], package=[], reference=str(reference),
                                          cli=cli, moon="unused", timeout=5)
                calls = []
                wrong_flags = False
                failed_flags = False
                def fake_execute(command, cwd, env, timeout, allowed=(0,)):
                    arguments = list(map(str, command))
                    calls.append(arguments)
                    if arguments[0] == str(reference):
                        if arguments[1:] == ["--version"]:
                            return subprocess.CompletedProcess(arguments, 0, "3.0.7\n", "")
                        if "--path" in arguments:
                            return subprocess.CompletedProcess(arguments, 0, str(directory / "app.pc"), "")
                        if "--print-requires" in arguments or "--print-requires-private" in arguments:
                            return subprocess.CompletedProcess(arguments, 0, "", "")
                        mode = arguments[len(REFERENCE_OPTIONS) + 1]
                    else:
                        mode = arguments[4]
                    value = "-DAPP" if mode == "--cflags" else "-lapp"
                    predicate = mode == "--exists" or "version=" in mode
                    matched = mode in ("--exists", "--atleast-version=0", "--max-version=999999999", "--exact-version=2")
                    code = int(predicate and not matched)
                    diagnostic = failed_flags and mode in ("--cflags", "--libs")
                    if diagnostic:
                        code = 1
                    if arguments[0] == str(reference):
                        output = "" if predicate or diagnostic else "2\n" if mode == "--modversion" else value + "\n"
                    else:
                        flags = [{"value": "-lwrong" if wrong_flags else value, "package": "app"}] if mode in ("--cflags", "--libs") else []
                        output = json.dumps({"schema_version": 1, "command": "query", "status": "diagnostics" if diagnostic else "nonmatch" if code else "ok",
                                             "error": None, "diagnostics": [{"code": "PC015"}] if diagnostic else [], "flags": flags,
                                             "value": "2" if mode == "--modversion" else None,
                                             "matched": matched if predicate else None})
                    return subprocess.CompletedProcess(arguments, code, output, "")
                with patch.dict(globals(), {"ROOT": directory}), patch("shutil.which", side_effect=lambda value: value), patch.dict(globals(), {"execute": fake_execute}):
                    report = {"cases": []}
                    verify(args, report)
                    self.assertTrue(report["passed"])
                    self.assertEqual(len(report["cases"]), 12)
                    self.assertEqual(sum("--print-requires" in call for call in calls), 1)
                    wrong_flags = True
                    failed = {"cases": []}
                    verify(args, failed)
                    self.assertFalse(failed["passed"])
                    self.assertEqual(failed["failed_cases"], 3)
                    wrong_flags, failed_flags = False, True
                    incomplete = {"cases": []}
                    verify(args, incomplete)
                    self.assertTrue(incomplete["passed"])
                    failures = [item for item in incomplete["cases"] if item.get("cli_status") == "diagnostics"]
                    self.assertEqual(len(failures), 3)
                    self.assertTrue(all(item["partial_flags"] and not item["arguments_compared"] for item in failures))

    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(HarnessTests))
    return 0 if result.wasSuccessful() else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, action="append", default=[])
    parser.add_argument("--package", action="append", default=[])
    parser.add_argument("--reference", default="pkgconf")
    parser.add_argument("--cli", type=Path)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--report", type=Path, default=ROOT / "_build/verification/system-packages.json")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.directory or args.timeout <= 0:
        parser.error("At least one --directory and a positive --timeout are required")
    report = {"schema_version": 1, "passed": False, "cases": [],
              "platform": {"system": platform.system(), "release": platform.release(), "machine": platform.machine()},
              "comparison": {"flags": "successful queries: exact argument value sets; duplicates ignored; order checked separately by the dependency-order invariant; failed queries: compare exits and preserve diagnostics/partial flags without treating them as evaluated arguments",
                             "system_filter": "disabled explicitly for both tools; reference keeps system Cflags and Libs",
                             "unsupported_inputs": "failures, never skipped",
                             "order": "reference dependency closure; all transitive relations with CLI flag origins; virtual providers resolved by reference --path"}}
    started = time.monotonic()
    args.report = args.report.resolve()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    def save():
        report["elapsed_seconds"] = round(time.monotonic() - started, 3)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    save()
    try:
        verify(args, report, save)
    except (OSError, ValueError, KeyError, TypeError, AssertionError, RuntimeError, subprocess.SubprocessError) as error:
        report["error"] = {"kind": type(error).__name__, "message": str(error)}
    finally:
        save()
    print(f"System corpus: {len(report['cases'])} queries, passed={report['passed']}; {args.report}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
