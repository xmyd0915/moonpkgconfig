"""Compare an explicit installed .pc corpus with pkgconf 3.0.7.

No packages are silently skipped. The report describes only the supplied
directories, not every package installed on the machine. --self-test exercises
the Python harness without MoonBit, pkgconf, or a system package installation.

Successful full Libs queries also require exact normalized sequences. The
normalizer is the fixed reference executable itself: a temporary linear .pc
chain contains ONLY the CLI's consecutive source-field segments in their
original order. No reference graph or expected sequence is used to reorder
them. This retains private repetitions and linker groups while applying the
reference's public-fragment merging rules. Cflags sequence agreement is
reported without an additional sequence assertion. --remove-package repeats
the corpus checks on byte-identical .pc copies with every copy of that id
removed, and requires a previously successful dependency query to fail.
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
FLAG_MODES = ("--cflags", "--libs", "--cflags-only-I", "--cflags-only-other",
              "--libs-only-L", "--libs-only-l", "--libs-only-other")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def flag_segments(flags):
    segments = []
    previous = None
    for flag in flags:
        key = (flag["package"], flag["field"], flag.get("location"))
        if flag["field"] not in ("Libs", "Libs.private", "Cflags", "Cflags.private"):
            raise ValueError(f"Unknown flag field: {flag['field']!r}")
        if key != previous:
            segments.append([flag["field"], []])
            previous = key
        if any(char in flag["value"] for char in "\x00\r\n"):
            raise ValueError("A fragment contains a control character unsupported by the .pc normalizer")
        segments[-1][1].append(flag["value"])
    return segments


class FragmentNormalizer:
    def __init__(self, reference, workspace, timeout):
        self.reference, self.workspace, self.timeout = reference, workspace, timeout
        self.cache = {}

    def normalize(self, flags, mode, static):
        segments = flag_segments(flags)
        key = json.dumps([segments, mode, static], ensure_ascii=False)
        if key in self.cache:
            return self.cache[key]
        if not segments:
            return []
        directory = self.workspace / hashlib.sha256(key.encode("utf-8")).hexdigest()
        directory.mkdir(parents=True, exist_ok=True)
        for index, (field, values) in enumerate(segments):
            # Quotes protect argv boundaries; .pc escapes protect literal text
            # from variable expansion and comment parsing before tokenization.
            value = shlex.join(values).replace("$", "$$").replace("#", "\\#")
            requires = f"Requires: f{index + 1}\n" if index + 1 < len(segments) else ""
            (directory / f"f{index}.pc").write_text(
                f"Name: f{index}\nDescription: ordered argument segments\nVersion: 1\n{requires}{field}: {value}\n",
                encoding="utf-8")
        result = execute([self.reference, *REFERENCE_OPTIONS, mode,
                          *(["--static"] if static else []), "f0"], ROOT,
                         clean_environment([directory]), self.timeout)
        normalized = shlex.split(result.stdout)
        self.cache[key] = normalized
        return normalized


def normalizer_probes(normalizer):
    def flags(public, private=()):
        return [{"package": "p", "field": field, "value": value}
                for field, values in (("Libs", public), ("Libs.private", private)) for value in values]
    cases = [
        ("public search paths first and libraries last", flags(["-L/a", "-lx", "-ly", "-lx", "-L/a"]),
         ["-L/a", "-ly", "-lx"]),
        ("private library repetition survives", flags(["-la", "-lb", "-la"], ["-la", "-lb", "-la"]),
         ["-lb", "-la", "-la", "-lb", "-la"]),
        ("group member repetition and order survive", flags(["-Wl,--start-group", "-la", "-lb", "-la", "-Wl,--end-group", "-la"]),
         ["-Wl,--start-group", "-la", "-lb", "-la", "-Wl,--end-group", "-la"]),
        ("literal argument boundaries survive", flags(["-L/sdk path", "-Wl,${literal}", "-Wl,#tag"]),
         ["-L/sdk path", "-Wl,${literal}", "-Wl,#tag"]),
    ]
    results = []
    for label, source, expected in cases:
        actual = normalizer.normalize(source, "--libs", True)
        if actual != expected:
            raise AssertionError(f"Reference normalization probe {label}: {actual} != {expected}")
        results.append({"case": label, "expected": expected, "actual": actual, "passed": True})
    negatives = [
        ("swapped distinct public libraries", flags(["-la", "-lb"]), flags(["-lb", "-la"])),
        ("removed private repeated library", flags([], ["-la", "-lb", "-la"]), flags([], ["-la", "-lb"])),
        ("swapped group members", flags(["-Wl,--start-group", "-la", "-lb", "-Wl,--end-group"]),
         flags(["-Wl,--start-group", "-lb", "-la", "-Wl,--end-group"])),
    ]
    for label, first, changed in negatives:
        if normalizer.normalize(first, "--libs", True) == normalizer.normalize(changed, "--libs", True):
            raise AssertionError(f"Normalization concealed {label}")
        results.append({"case": label, "changed_sequence_rejected": True, "passed": True})
    return results


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


def expanded_size(data):
    if (data.get("schema_version") != 1 or data.get("command") != "inspect"
            or data.get("status") != "ok" or data.get("diagnostics") or data.get("error") is not None):
        raise ValueError("Expansion measurement requires a successful inspect JSON report")
    values = [entry["value"] for entry in data["entries"]]
    if any(not isinstance(value, str) for value in values):
        raise ValueError("Inspection contains a non-string expanded value")
    units = [len(value.encode("utf-16-le")) // 2 for value in values]
    return {"entry_count": len(values), "expanded_codepoints": sum(map(len, values)),
            "expanded_utf16_units": sum(units), "largest_value_utf16_units": max(units, default=0)}


def measure_expansions(selected, cli, env, timeout):
    records = []
    for name, path in sorted(selected.items()):
        record = {"package": name, "path": str(path), "passed": False}
        records.append(record)
        try:
            result = execute([cli, "inspect", path, "--json"], ROOT, env, timeout)
            record.update(expanded_size(json.loads(result.stdout)), passed=True)
        except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
            record["error"] = {"kind": type(error).__name__, "message": str(error)}
            if isinstance(error, subprocess.TimeoutExpired):
                raise
    valid = [record for record in records if record["passed"]]
    maximum = max(valid, key=lambda record: record["expanded_utf16_units"], default=None)
    return {"records": records, "passed": len(valid) == len(records), "maximum": maximum,
            "measurement": "sum of every inspect entry's expanded value, including variables and fields; UTF-16 units and Unicode codepoints both recorded",
            "candidate_budget_headroom": {str(limit): None if maximum is None else {
                "unused_utf16_units": limit - maximum["expanded_utf16_units"],
                "multiple_of_observed_maximum": limit / max(1, maximum["expanded_utf16_units"])}
                for limit in (65536, 262144, 1048576, 16777216)}}


def copy_without_packages(directories, destination, removed):
    selected, original = inventory(directories)
    if not removed or set(removed) - set(selected):
        raise ValueError("Every --remove-package must name a selected package in the source corpus")
    copied, deleted, copies = [], [], []
    for index, source in enumerate(directories):
        target = destination / f"directory-{index}"
        target.mkdir(parents=True)
        copies.append(target)
        for path in sorted(source.iterdir(), key=lambda path: path.name):
            if not path.name.endswith(".pc"):
                continue
            copy = target / path.name
            shutil.copyfile(path, copy)
            checksum = digest(path)
            if digest(copy) != checksum:
                raise AssertionError(f"Corpus copy differs from source metadata: {path}")
            item = {"source": str(path), "copy": str(copy), "sha256": checksum}
            copied.append(item)
            if path.name[:-3] in removed:
                # This is a newly-created flat file in this invocation's own
                # directory. Symlinks are dereferenced when copying, never kept.
                if copy.resolve().parent != target.resolve():
                    raise ValueError("Mutation target escaped its generated directory")
                copy.unlink()
                deleted.append(item)
    after, _ = inventory(copies)
    if set(removed) & set(after):
        raise AssertionError("A removed package still exists in a lower-priority directory")
    return copies, {"removed_packages": sorted(removed), "copied_files": copied,
                    "deleted_files": deleted, "source_files": original}


def mutation_effect(baseline, mutated, removed):
    previous = {(item["package"], item["mode"], item.get("static", False)): item
                for item in baseline["cases"]}
    affected = []
    for item in mutated["cases"]:
        old = previous.get((item["package"], item["mode"], item.get("static", False)))
        if (item["mode"] in FLAG_MODES and old and old.get("passed") and old.get("cli_exit") == 0
                and item.get("passed") and item.get("reference_exit") == item.get("cli_exit") == 1
                and any(problem.get("code") == "PC015" and any(
                    problem.get("message", "").endswith(": " + name) for name in removed)
                    for problem in item.get("diagnostics", []))):
            affected.append({"package": item["package"], "mode": item["mode"], "static": item["static"]})
    if not affected:
        raise AssertionError("Removing metadata did not turn any successful real dependency flag query into matching PC015 failures")
    return affected


def verify_with_mutation(args, report, checkpoint=None):
    verify(args, report, checkpoint)
    if not args.remove_package:
        return
    if not report["passed"]:
        report["mutation"] = {"passed": False, "not_run_reason": "Original corpus comparisons failed"}
        return
    report["passed"] = False
    source_directories = [path.resolve() for path in args.directory]
    temporary = ROOT / ".tmp"
    destination = Path(tempfile.mkdtemp(prefix="system-mutation-", dir=temporary)).resolve()
    mutated = {"passed": False, "cases": []}
    report["mutation"] = mutated
    try:
        directories, evidence = copy_without_packages(source_directories, destination, set(args.remove_package))
        mutated.update(evidence)
        if set(args.package) & set(args.remove_package):
            raise ValueError("A selected --package cannot also be removed from the corpus")
        options = argparse.Namespace(**vars(args))
        options.directory, options.cli, options.remove_package = directories, Path(report["cli"]["path"]), []
        verify(options, mutated, checkpoint)
        affected = mutation_effect(report, mutated, args.remove_package)
        mutated["dependency_failure_transitions"] = affected
        mutated["dependency_failure_count"] = len(affected)
    finally:
        _, after = inventory(source_directories)
        mutated["source_metadata_unchanged"] = after == report["files"]
        if not mutated["source_metadata_unchanged"]:
            raise AssertionError("Mutation verification changed the original metadata corpus")
    report["passed"] = mutated["passed"] and mutated["source_metadata_unchanged"]


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
        cacheable = arguments[0] in ("--print-requires", "--print-requires-private", "--path", "--print-variables")
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
    report["selected_variables"] = {}
    corpus = Corpus(selected, reference_query)
    normalizer = FragmentNormalizer(reference, workspace / "fragments", args.timeout)
    report["normalizer_probes"] = normalizer_probes(normalizer)
    report["expansion_measurements"] = measure_expansions(selected, cli, env, args.timeout)
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
            if mode in FLAG_MODES:
                if ref.returncode == 0:
                    reference_sequence = shlex.split(ref.stdout)
                    normalized = normalizer.normalize(data["flags"], mode, static)
                    expected, returned = sorted(set(reference_sequence)), sorted(set(normalized))
                    record.update(reference_flags=expected, flags=sorted({flag["value"] for flag in data["flags"]}),
                                  normalized_sequence=normalized, reference_sequence=reference_sequence,
                                  sequence_equal=normalized == reference_sequence,
                                  sequence_asserted=mode == "--libs", arguments_compared=True)
                    if expected != returned:
                        raise AssertionError(f"Argument sets differ: missing={sorted(set(expected)-set(returned))}, extra={sorted(set(returned)-set(expected))}")
                    if mode == "--libs":
                        if normalized != reference_sequence:
                            raise AssertionError(f"Normalized Libs sequence differs: {normalized} != {reference_sequence}")
                        graph = corpus.closure(name, static)
                        record["dependency_graph"] = graph
                        record["order"] = check_order(data["flags"], graph, name)
                else:
                    if data["status"] != "diagnostics" or data["matched"] is not None:
                        raise AssertionError("Failed flag query must report unevaluated diagnostics")
                    record.update(arguments_compared=False, partial_flags=data["flags"],
                                  reference_partial_stdout=ref.stdout,
                                  comparison_note="Both queries failed; partial JSON flags are diagnostic evidence, not evaluated arguments")
            elif mode == "--modversion" or mode.startswith("--variable="):
                expected = ref.stdout.rstrip("\r\n")
                record.update(reference_value=expected, value=data["value"])
                if ref.returncode == 0 and data["value"] != expected:
                    raise AssertionError("Metadata values differ")
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
            variables = reference_query(["--print-variables", name], allowed=(0,)).stdout.splitlines()
            # Loader-provided builtins are expansion inputs, not source variable
            # entries in this CLI. Compare one real variable whenever present.
            variables = sorted(set(variables) - {"pcfiledir", "pc_sysrootdir", "pc_top_builddir"})
            if variables:
                report["selected_variables"][name] = "prefix" if "prefix" in variables else variables[0]
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            report["cases"].append({"package": name, "mode": "source-selection", "passed": False,
                                    "error": {"kind": type(error).__name__, "message": str(error)}})
            if isinstance(error, subprocess.TimeoutExpired):
                raise
        version_data = case(name, "--modversion")
        if name in report["selected_variables"]:
            case(name, "--variable=" + report["selected_variables"][name])
        for mode in FLAG_MODES:
            for static in (False, True):
                case(name, mode, static)
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
    report["normalized_fragment_queries"] = len(normalizer.cache)
    agreements = {}
    for record in report["cases"]:
        if "sequence_equal" in record:
            key = record["mode"] + (" --static" if record["static"] else "")
            item = agreements.setdefault(key, {"compared": 0, "equal": 0, "asserted": record["sequence_asserted"]})
            item["compared"] += 1
            item["equal"] += int(record["sequence_equal"])
    for item in agreements.values():
        item["agreement_rate"] = item["equal"] / item["compared"]
    report["sequence_agreement"] = agreements
    _, after = inventory(directories)
    report["metadata_unchanged"] = files == after
    if not report["metadata_unchanged"]:
        raise AssertionError("The metadata corpus changed while verification was running")
    report["cli_unchanged"] = digest(cli) == report["cli"]["sha256"]
    if not report["cli_unchanged"]:
        raise AssertionError("The CLI executable changed while verification was running")
    report["failed_cases"] = sum(not item["passed"] for item in report["cases"])
    report["passed"] = report["failed_cases"] == 0 and report["expansion_measurements"]["passed"]


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

        def test_expansion_measurement_counts_utf16_and_rejects_errors(self):
            report = {"schema_version": 1, "command": "inspect", "status": "ok",
                      "diagnostics": [], "error": None,
                      "entries": [{"value": "a\U0001f642"}, {"value": "123"}]}
            self.assertEqual(expanded_size(report), {
                "entry_count": 2, "expanded_codepoints": 5,
                "expanded_utf16_units": 6, "largest_value_utf16_units": 3})
            report["status"] = "diagnostics"
            with self.assertRaises(ValueError):
                expanded_size(report)

        def test_copy_removes_shadowed_files_without_changing_sources(self):
            with tempfile.TemporaryDirectory() as temporary:
                base = Path(temporary)
                first, second = base / "first", base / "second"
                first.mkdir()
                second.mkdir()
                (first / "zlib.pc").write_text("first zlib", encoding="utf-8")
                (second / "zlib.pc").write_text("second zlib", encoding="utf-8")
                (first / "app.pc").write_text("root", encoding="utf-8")
                _, before = inventory([first, second])
                copies, evidence = copy_without_packages([first, second], base / "copies", {"zlib"})
                selected, _ = inventory(copies)
                self.assertEqual(set(selected), {"app"})
                self.assertEqual(len(evidence["deleted_files"]), 2)
                self.assertEqual(len(evidence["copied_files"]), 3)
                self.assertTrue(all(not Path(item["copy"]).exists() for item in evidence["deleted_files"]))
                self.assertEqual(inventory([first, second])[1], before)
                with self.assertRaises(ValueError):
                    copy_without_packages([first, second], base / "bad", {"missing"})

        def test_mutation_requires_a_new_matching_dependency_flag_failure(self):
            before = {"cases": [{"package": "app", "mode": "--libs", "static": True,
                                 "passed": True, "cli_exit": 0}]}
            item = {"package": "app", "mode": "--libs", "static": True, "passed": True,
                    "cli_exit": 1, "reference_exit": 1,
                    "diagnostics": [{"code": "PC015", "message": "Required package not found: zlib"}]}
            self.assertEqual(mutation_effect(before, {"cases": [item]}, ["zlib"]),
                             [{"package": "app", "mode": "--libs", "static": True}])
            for changed in ({**item, "reference_exit": 0}, {**item, "passed": False},
                            {**item, "mode": "--exists"}, {**item, "diagnostics": []}):
                with self.assertRaises(AssertionError):
                    mutation_effect(before, {"cases": [changed]}, ["zlib"])

        def test_normalizer_keeps_actual_segment_order_and_private_membership(self):
            from unittest.mock import patch
            flags = [
                {"package": "later", "field": "Libs", "value": "-lb"},
                {"package": "later", "field": "Libs.private", "value": "-lp"},
                {"package": "later", "field": "Libs.private", "value": "-lp"},
                {"package": "earlier", "field": "Libs", "value": "-la"},
                {"package": "later", "field": "Libs", "value": "-lb"},
            ]
            with tempfile.TemporaryDirectory() as temporary:
                def reference(command, cwd, env, timeout, allowed=(0,)):
                    directory = Path(env["PKG_CONFIG_LIBDIR"])
                    documents = [(directory / f"f{i}.pc").read_text(encoding="utf-8") for i in range(4)]
                    self.assertIn("Requires: f1\nLibs: -lb\n", documents[0])
                    self.assertIn("Requires: f2\nLibs.private: -lp -lp\n", documents[1])
                    self.assertIn("Requires: f3\nLibs: -la\n", documents[2])
                    self.assertTrue(documents[3].endswith("Libs: -lb\n"))
                    self.assertNotIn("Requires:", documents[3])
                    return subprocess.CompletedProcess(command, 0, "-lp -lp -la -lb", "")
                normalizer = FragmentNormalizer("reference", Path(temporary), 5)
                with patch.dict(globals(), {"execute": reference}):
                    self.assertEqual(normalizer.normalize(flags, "--libs", True), ["-lp", "-lp", "-la", "-lb"])
                self.assertEqual(normalizer.normalize(flags, "--libs", True), ["-lp", "-lp", "-la", "-lb"])
                with self.assertRaises(ValueError):
                    flag_segments([{**flags[0], "value": "-lbad\nLibs: -linjected"}])

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
                reordered_flags = False
                values = {"--cflags": ["-I/include", "-DAPP"], "--libs": ["-L/lib", "-lapp", "-lbase"],
                          "--cflags-only-I": ["-I/include"], "--cflags-only-other": ["-DAPP"],
                          "--libs-only-L": ["-L/lib"], "--libs-only-l": ["-lapp", "-lbase"],
                          "--libs-only-other": []}
                class IdentityNormalizer:
                    def __init__(self, *arguments):
                        self.cache = {}
                    def normalize(self, flags, mode, static):
                        return [flag["value"] for flag in flags]
                def fake_execute(command, cwd, env, timeout, allowed=(0,)):
                    arguments = list(map(str, command))
                    calls.append(arguments)
                    if arguments[0] == str(reference):
                        if arguments[1:] == ["--version"]:
                            return subprocess.CompletedProcess(arguments, 0, "3.0.7\n", "")
                        if "--path" in arguments:
                            return subprocess.CompletedProcess(arguments, 0, str(directory / "app.pc"), "")
                        if any(option in arguments for option in ("--print-requires", "--print-requires-private", "--print-variables")):
                            return subprocess.CompletedProcess(arguments, 0, "", "")
                        mode = arguments[len(REFERENCE_OPTIONS) + 1]
                    else:
                        if arguments[1] == "inspect":
                            return subprocess.CompletedProcess(arguments, 0, json.dumps({
                                "schema_version": 1, "command": "inspect", "status": "ok",
                                "diagnostics": [], "error": None, "entries": [{"value": "app"}]}), "")
                        mode = arguments[4]
                    predicate = mode == "--exists" or "version=" in mode
                    matched = mode in ("--exists", "--atleast-version=0", "--max-version=999999999", "--exact-version=2")
                    code = int(predicate and not matched)
                    diagnostic = failed_flags and mode in FLAG_MODES
                    if diagnostic:
                        code = 1
                    if arguments[0] == str(reference):
                        output = "" if predicate or diagnostic else "2\n" if mode == "--modversion" else shlex.join(values[mode]) + "\n"
                    else:
                        returned = ["-lwrong"] if wrong_flags and mode in FLAG_MODES else list(values.get(mode, []))
                        if reordered_flags and mode == "--libs":
                            returned.reverse()
                        flags = [{"value": value, "package": "app",
                                  "field": "Cflags" if mode.startswith("--cflags") else "Libs"} for value in returned]
                        output = json.dumps({"schema_version": 1, "command": "query", "status": "diagnostics" if diagnostic else "nonmatch" if code else "ok",
                                             "error": None, "diagnostics": [{"code": "PC015"}] if diagnostic else [], "flags": flags,
                                             "value": "2" if mode == "--modversion" else None,
                                             "matched": matched if predicate else None})
                    return subprocess.CompletedProcess(arguments, code, output, "")
                with patch.dict(globals(), {"ROOT": directory, "execute": fake_execute,
                                           "FragmentNormalizer": IdentityNormalizer, "normalizer_probes": lambda normalizer: []}), \
                        patch("shutil.which", side_effect=lambda value: value):
                    report = {"cases": []}
                    verify(args, report)
                    self.assertTrue(report["passed"])
                    self.assertEqual(len(report["cases"]), 23)
                    self.assertEqual(sum("--print-requires" in call for call in calls), 1)
                    wrong_flags = True
                    failed = {"cases": []}
                    verify(args, failed)
                    self.assertFalse(failed["passed"])
                    self.assertEqual(failed["failed_cases"], 14)
                    wrong_flags, reordered_flags = False, True
                    wrong_order = {"cases": []}
                    verify(args, wrong_order)
                    self.assertFalse(wrong_order["passed"])
                    self.assertEqual(wrong_order["failed_cases"], 2)
                    reordered_flags = False
                    wrong_flags, failed_flags = False, True
                    incomplete = {"cases": []}
                    verify(args, incomplete)
                    self.assertTrue(incomplete["passed"])
                    failures = [item for item in incomplete["cases"] if item.get("cli_status") == "diagnostics"]
                    self.assertEqual(len(failures), 14)
                    self.assertTrue(all("partial_flags" in item and not item["arguments_compared"] for item in failures))

    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(HarnessTests))
    return 0 if result.wasSuccessful() else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, action="append", default=[])
    parser.add_argument("--package", action="append", default=[])
    parser.add_argument("--remove-package", action="append", default=[],
                        help="repeat all checks on copied metadata with this id removed; require dependency failures")
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
              "comparison": {"flags": "successful queries: normalized argument sets for all flag modes and exact normalized sequences for full --libs; Cflags/classified sequence agreement is recorded, not asserted; failed queries preserve diagnostics/partial flags without treating them as evaluated arguments",
                             "normalization": "pkgconf 3.0.7 evaluates a linear .pc chain of the CLI's actual consecutive source-field segments, in exactly their original order; no reference graph or expected sequence is used to reorder input; private repetitions and group contents retain reference semantics",
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
        verify_with_mutation(args, report, save)
    except (OSError, ValueError, KeyError, TypeError, AssertionError, RuntimeError, subprocess.SubprocessError) as error:
        report["error"] = {"kind": type(error).__name__, "message": str(error)}
    finally:
        save()
    print(f"System corpus: {len(report['cases'])} queries, passed={report['passed']}; {args.report}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
