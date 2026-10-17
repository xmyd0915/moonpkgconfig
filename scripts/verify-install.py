"""Verify the public API from a packaged archive or a fresh registry install."""

import argparse
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parent.parent
MODULE = "xmyd0915/moonpkgconfig"
SMOKE = r'''
///|
fn fixture_document(name : String, requires : String, libs : String, extra : String) -> @pc.Document {
  @pc.parse("Name: " + name + "\nDescription: installed consumer\nVersion: 1\nRequires: " + requires + "\nLibs: " + libs + "\n" + extra, source=name + ".pc")
}

///|
test "installed flag selection retains static libraries and origins" {
  let packages = @pc.PackageSet::new()
  @debug.assert_eq(packages.add("root", fixture_document("root", "public", "-L/sdk/lib -lroot", "Requires.private: private\nLibs.private: -lm")), [])
  @debug.assert_eq(packages.add("public", fixture_document("public", "", "-lpublic", "")), [])
  @debug.assert_eq(packages.add("private", fixture_document("private", "", "-lprivate", "")), [])
  let selected = packages.collect_libs("root", static_linking=true).select(@pc.Libraries)
  @debug.assert_eq(selected.diagnostics, [])
  @debug.assert_eq(selected.flags.map(f => f.value), ["-lroot", "-lm", "-lpublic", "-lprivate"])
  @debug.assert_eq(selected.flags[1].field, "Libs.private")
  @debug.assert_eq(selected.flags[1].location.source, "root.pc")
  @debug.assert_eq(packages.collect_libs("root").select(@pc.LibraryPaths).flags.map(f => f.value), ["-L/sdk/lib"])
  @debug.assert_eq(packages.check_all(), [])
}

///|
test "installed path snapshots and provider queries refresh correctly" {
  let packages = @pc.PackageSet::new()
  packages.add("root", fixture_document("root", "virtual >= 2", "-lroot", "")) |> ignore
  let before = packages.dependency_paths("root")
  @debug.assert_eq(packages.resolve("root").diagnostics.map(d => d.code), ["PC015"])
  packages.add("provider", fixture_document("provider", "", "-lprovider", "Provides: virtual = 3")) |> ignore
  let after = packages.dependency_paths("root")
  @debug.assert_eq(before.path_to("provider"), [])
  @debug.assert_eq(after.path_to("provider"), ["root", "provider"])
  @debug.assert_eq(packages.resolve("root").order, ["provider", "root"])
  @debug.assert_eq(packages.collect_libs("root").select(@pc.Libraries).flags.map(f => f.value), ["-lroot", "-lprovider"])
}

///|
test "installed core handles deep directory checks" {
  let packages = @pc.PackageSet::new()
  for i = 0; i < 5000; i = i + 1 {
    let requires = if i < 4999 { "p\{i + 1}" } else { "" }
    packages.add("p\{i}", fixture_document("p\{i}", requires, "", "")) |> ignore
  }
  @debug.assert_eq(packages.check_all(), [])
  let path = packages.dependency_paths("p0").path_to("p4999")
  assert_eq(path.length(), 5000)
  assert_eq(path[0], "p0")
  assert_eq(path[4999], "p4999")
}
'''


def version_from(directory):
    text = (directory / "moon.mod").read_text(encoding="utf-8")
    name = re.search(r'^name\s*=\s*"([^"]+)"', text, re.MULTILINE)
    version = re.search(r'^version\s*=\s*"([^"]+)"', text, re.MULTILINE)
    if name is None or name.group(1) != MODULE or version is None:
        raise RuntimeError("Unexpected module metadata")
    return version.group(1)


def run(command, directory):
    subprocess.run(command, cwd=directory, check=True)


def extract_package(archive, destination):
    required = {
        "moon.mod", "moon.pkg", "LICENSE", "ORIGINS.md", "parser.mbt", "flags.mbt",
        "flag_selection.mbt", "dependency_paths.mbt", "query_context.mbt", "directory_check.mbt",
    }
    with zipfile.ZipFile(archive) as package:
        names = set(package.namelist())
        if not required.issubset(names):
            raise RuntimeError(f"Package is missing required files: {sorted(required - names)}")
        for entry in package.infolist():
            path = Path(entry.filename.replace("\\", "/"))
            target = (destination / path).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise RuntimeError("Archive path leaves extraction directory")
            if any(part in {"_build", "target", ".tools", ".mooncakes", ".git"} or part.startswith(".tmp") for part in path.parts):
                raise RuntimeError(f"Package contains a temporary artifact: {entry.filename}")
            if path.name == "credentials.json" or stat.S_ISLNK(entry.external_attr >> 16):
                raise RuntimeError("Package contains credentials or a symbolic link")
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(package.read(entry))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--package", action="store_true", help="package the current source before testing")
    mode.add_argument("--archive", type=Path, help="test one existing package archive")
    parser.add_argument("--version", default=version_from(ROOT))
    args = parser.parse_args()
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?", args.version) is None:
        parser.error("version must be a semantic version")
    moon = shutil.which("moon")
    if moon is None:
        parser.error("MoonBit CLI must be installed")
    archive = args.archive.resolve() if args.archive else None
    if args.package:
        run([moon, "package"], ROOT)
        archive = ROOT / "_build/publish" / f"{MODULE.replace('/', '-')}-{args.version}.zip"
    temporary = ROOT / ".tmp"
    temporary.mkdir(exist_ok=True)
    working = Path(tempfile.mkdtemp(prefix="install-" + args.version + "-", dir=temporary)).resolve()
    consumer = working / "consumer"
    consumer.mkdir()
    if archive:
        source = working / "source"
        source.mkdir()
        extract_package(archive, source)
        if version_from(source) != args.version:
            raise RuntimeError("Archive version does not match requested version")
        (working / "moon.work").write_text('members = ["consumer", "source"]\n', encoding="utf-8")
    else:
        (consumer / "moon.mod").write_text('name = "verification/moonpkgconfig-consumer"\n', encoding="utf-8")
        run([moon, "add", MODULE + "@" + args.version], consumer)
    if archive:
        (consumer / "moon.mod").write_text('name = "verification/moonpkgconfig-consumer"\nimport { "' + MODULE + '@' + args.version + '" }\n', encoding="utf-8")
    (consumer / "moon.pkg").write_text('import { "' + MODULE + '" @pc, "moonbitlang/core/debug", } for "test"\n', encoding="utf-8")
    (consumer / "consumer_test.mbt").write_text(SMOKE, encoding="utf-8")
    run([moon, "fmt"], consumer)
    run([moon, "check", "--target", "all", "--deny-warn"], consumer)
    if not archive:
        installed = consumer / ".mooncakes" / MODULE
        if version_from(installed) != args.version:
            raise RuntimeError("Installed version differs from requested release")
    run([moon, "test", "--target", "all", "--deny-warn"], consumer)
    origin = "packaged archive" if archive else "MoonCakes registry"
    print(f"Installed public API: {MODULE}@{args.version}; {origin}; 3 tests on 4 targets passed")
    print(f"Consumer project: {consumer}")


if __name__ == "__main__":
    main()
