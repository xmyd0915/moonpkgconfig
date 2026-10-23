"""Build the published generic template and verify a real zlib file application."""

import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import zlib


ROOT = Path(__file__).resolve().parent.parent
DEPENDENCY = "xmyd0915/moonpkgconfig@0.3.1"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def template_hashes(directory):
    return {
        path.relative_to(directory).as_posix(): digest(path)
        for path in sorted(directory.rglob("*"))
        if path.is_file() and not any(part in ("_build", ".mooncakes", "__pycache__")
                                      for part in path.relative_to(directory).parts)
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pc-dir", type=Path, required=True,
                        help="directory containing the real installed zlib.pc")
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--cc")
    parser.add_argument("--msvc-lib", action="append", default=[], metavar="NAME=FILE.lib")
    args = parser.parse_args()
    destination = ROOT / "_build/verification/native-file-tool.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    evidence = {"dependency": DEPENDENCY, "platform": sys.platform,
                "cases": [], "files": [], "passed": False}

    def save():
        destination.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n",
                               encoding="utf-8")

    save()
    try:
        directory = args.pc_dir.resolve()
        installed_pc = directory / "zlib.pc"
        installed_hash = digest(installed_pc)
        working = Path(tempfile.mkdtemp(prefix="native-file-tool-")).resolve()
        consumer = working / "consumer"
        source = ROOT / "examples/native-consumer"
        shutil.copytree(source, consumer,
                        ignore=shutil.ignore_patterns("_build", ".mooncakes", "__pycache__"))
        hashes = template_hashes(consumer)
        if hashes != template_hashes(source):
            raise RuntimeError("The standalone copy differs from the checked-in template")
        application = consumer / "apps/zlib-files"
        overrides = working / "overrides"
        overrides.mkdir()
        malformed_pc = overrides / "zlib.pc"
        malformed_pc.write_text(
            "prefix=${missing}\nName: zlib\nDescription: temporary broken override\nVersion: 1.3.1\n",
            encoding="utf-8")
        command = [sys.executable, str(consumer / "build.py"), "--config",
                   str(application / "consumer.json"), "--moon", args.moon,
                   "--pc-dir", str(overrides), "--pc-dir", str(directory)]
        if args.cc:
            command.extend(["--cc", args.cc])
        for mapping in args.msvc_lib:
            command.extend(["--msvc-lib", mapping])
        evidence.update({"consumer": str(consumer), "metadata": str(installed_pc),
                         "metadata_sha256": installed_hash,
                         "template_sha256": {name: hashes[name] for name in ("build.py", "cmd/plan/main.mbt")},
                         "consumer_sha256": hashes,
                         "build_command": command, "python_zlib": zlib.ZLIB_RUNTIME_VERSION})

        def build(label, expected_status):
            earlier = set(consumer.glob("_build/consumer-*/evidence.json"))
            print(label, flush=True)
            result = subprocess.run(command, cwd=consumer, text=True, encoding="utf-8",
                                    errors="replace", capture_output=True)
            record = {"case": label, "exit": result.returncode,
                      "stdout": result.stdout, "stderr": result.stderr}
            evidence["cases"].append(record)
            print(result.stdout + result.stderr, flush=True)
            reports = set(consumer.glob("_build/consumer-*/evidence.json")) - earlier
            if len(reports) != 1:
                raise RuntimeError("Expected one evidence report from the generic adapter")
            report = reports.pop()
            data = json.loads(report.read_text(encoding="utf-8"))
            record.update({"report": str(report), "result": data})
            if result.returncode != expected_status:
                raise RuntimeError(f"Expected exit {expected_status}, got {result.returncode}")
            if data["dependency"] != DEPENDENCY:
                raise RuntimeError("The generic adapter did not use the published 0.3.1 package")
            return data

        broken = build("malformed transitive dependency", 1)
        if broken["built"] or "executable" in broken:
            raise RuntimeError("Malformed metadata reached native compilation")
        for section in ("cflags", "libs"):
            problems = broken["plan"][section]["diagnostics"]
            if (len(problems) != 1 or problems[0]["code"] != "PC004"
                    or Path(problems[0]["location"]["source"]) != malformed_pc
                    or problems[0]["location"]["line"] != 1
                    or problems[0]["location"]["column"] != 8):
                raise RuntimeError("Malformed dependency did not retain its exact source diagnostic")

        # Remove only the temporary override; the installed metadata stays untouched.
        malformed_pc.unlink()
        repaired = build("repaired build using the installed dependency", 0)
        if not repaired["built"] or any(repaired["plan"][key]["diagnostics"]
                                        for key in ("cflags", "libs")):
            raise RuntimeError("The repaired dependency did not produce a clean native build")
        dependency = next(item for item in repaired["plan"]["dependencies"]
                          if item["package"] == "zlib")
        if dependency["path"] != ["native-app", "zlib"]:
            raise RuntimeError("The dependency plan lost the private route to zlib")
        for section in ("cflags", "libs"):
            flags = repaired["plan"][section]["flags"]
            if not flags or any(Path(flag["location"]["source"]) != installed_pc
                                or flag["package"] != "zlib" for flag in flags):
                raise RuntimeError("Compiler arguments lost the real installed metadata origins")
        executable = Path(repaired["executable"])
        if not executable.is_file() or not executable.resolve().is_relative_to(consumer):
            raise RuntimeError("The adapter did not return a standalone consumer executable")
        evidence["executable"] = str(executable)
        files = working / "files"
        files.mkdir()

        def execute(label, arguments, status):
            invocation = [str(executable), *map(str, arguments)]
            result = subprocess.run(invocation, cwd=files, text=True, encoding="utf-8",
                                    errors="replace", capture_output=True, timeout=30)
            evidence["cases"].append({"case": label, "command": invocation,
                                      "exit": result.returncode, "stdout": result.stdout,
                                      "stderr": result.stderr})
            if result.returncode != status:
                raise RuntimeError(f"{label}: expected exit {status}, got {result.returncode}: "
                                   f"{result.stdout}{result.stderr}")
            return result

        for label, content in (
            ("empty", b""),
            ("text", "MoonPkgConfig builds a file tool.\n\u538b\u7f29\u548c\u89e3\u538b\u7f29\u3002\n".encode("utf-8") * 100),
            ("binary", bytes(range(256)) * 2048),
            ("\u8def\u5f84 with spaces \U0001f680", b"Unicode filenames and spaces\n"),
        ):
            original = files / (label + ".input")
            compressed = files / (label + ".zlib")
            restored = files / (label + ".restored")
            python_compressed = files / (label + ".python-zlib")
            python_restored = files / (label + ".python-restored")
            original.write_bytes(content)
            execute(label + " compression", ("compress", original, compressed), 0)
            execute(label + " decompression", ("decompress", compressed, restored), 0)
            if restored.read_bytes() != content:
                raise RuntimeError(f"The file round trip differs: {label}")
            if zlib.decompress(compressed.read_bytes()) != content:
                raise RuntimeError(f"Python zlib could not reproduce the input: {label}")
            python_compressed.write_bytes(zlib.compress(content))
            execute(label + " Python stream decompression",
                    ("decompress", python_compressed, python_restored), 0)
            if python_restored.read_bytes() != content:
                raise RuntimeError(f"The file tool could not read Python zlib output: {label}")
            evidence["files"].append({"input": label, "bytes": len(content),
                                      "sha256": digest(original), "compressed_sha256": digest(compressed),
                                      "round_trip": True, "python_reads_output": True,
                                      "reads_python_output": True})

        corrupt = files / "corrupt.zlib"
        rejected = files / "corrupt.output"
        corrupt.write_bytes(b"not a zlib stream")
        execute("corrupt input rejected", ("decompress", corrupt, rejected), 1)
        if rejected.exists():
            raise RuntimeError("Corrupt input created an output file")
        preserved = files / "existing.output"
        preserved.write_bytes(b"keep this file")
        execute("existing output preserved", ("compress", original, preserved), 1)
        if preserved.read_bytes() != b"keep this file":
            raise RuntimeError("An existing output file was overwritten")
        execute("same input and output rejected", ("compress", original, original), 1)
        if original.read_bytes() != content:
            raise RuntimeError("The input file was changed")
        missing_output = files / "missing.output"
        execute("missing input rejected", ("compress", files / "absent.input", missing_output), 1)
        if missing_output.exists():
            raise RuntimeError("A missing input created an output file")
        execute("usage error", (), 2)

        boundary = files / "limit.input"
        boundary_stream = files / "limit.zlib"
        boundary_restored = files / "limit.restored"
        with boundary.open("wb") as stream:
            stream.truncate(64 * 1024 * 1024)
        execute("input size limit accepted", ("compress", boundary, boundary_stream), 0)
        execute("output size limit accepted", ("decompress", boundary_stream, boundary_restored), 0)
        if boundary_restored.stat().st_size != boundary.stat().st_size or digest(boundary_restored) != digest(boundary):
            raise RuntimeError("The exact 64 MiB boundary did not round trip")
        evidence["size_boundary"] = {"bytes": boundary.stat().st_size, "round_trip": True}

        # Sparse/truncated inputs exercise the limit without storing a large
        # fixture in the repository. Both modes must fail before producing output.
        oversized = files / "oversized.input"
        oversized_output = files / "oversized.output"
        for mode, size in (("compress", 64 * 1024 * 1024 + 1),
                           ("decompress", 65 * 1024 * 1024)):
            with oversized.open("wb") as stream:
                stream.truncate(size)
            rejected_size = execute(mode + " oversized input rejected",
                                    (mode, oversized, oversized_output), 1)
            if "Input exceeds the supported size" not in rejected_size.stdout:
                raise RuntimeError("Oversized input did not produce a controlled size error")
            if oversized_output.exists():
                raise RuntimeError("Oversized input created an output file")

        # A valid stream whose decoded contents exceed the output limit must
        # also fail without creating an output file.
        expanded = files / "expands-over-limit.zlib"
        compressor = zlib.compressobj()
        with expanded.open("wb") as stream:
            for _ in range(1024):
                stream.write(compressor.compress(bytes(65536)))
            stream.write(compressor.compress(b"x") + compressor.flush())
        execute("decompressed output limit", ("decompress", expanded, oversized_output), 1)
        if oversized_output.exists():
            raise RuntimeError("Excessive decompressed output created a file")

        existing_directory = files / "existing.directory"
        existing_directory.mkdir()
        sentinel = existing_directory / "keep.txt"
        sentinel.write_bytes(b"keep directory contents")
        execute("existing output directory preserved",
                ("compress", original, existing_directory), 1)
        if sentinel.read_bytes() != b"keep directory contents":
            raise RuntimeError("An output creation error removed an existing directory")
        execute("output creation error preserves input",
                ("compress", original, files / "absent.directory" / "output"), 1)
        if original.read_bytes() != content:
            raise RuntimeError("An output creation error changed the input")

        dangling = files / "dangling.output"
        link_target = files / "must-not-be-created"
        try:
            dangling.symlink_to(link_target)
        except (OSError, NotImplementedError) as error:
            evidence["symlink_check"] = {"skipped": True, "reason": str(error)}
        else:
            execute("dangling output symlink rejected", ("compress", original, dangling), 1)
            if not dangling.is_symlink() or link_target.exists():
                raise RuntimeError("A dangling output link was followed or removed")
            evidence["symlink_check"] = {"skipped": False, "passed": True}

        # On POSIX a FIFO lets the verifier create the destination after the
        # application's early path check. Exclusive creation must still refuse
        # it, and the error must not unlink or overwrite the competing file.
        if os.name == "posix":
            fifo = files / "delayed.input"
            raced = files / "concurrent.output"
            os.mkfifo(fifo)
            invocation = [str(executable), "compress", str(fifo), str(raced)]
            process = subprocess.Popen(invocation, cwd=files, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True, encoding="utf-8")
            try:
                # Wait until the application opens the input, which follows its
                # early output check. Nonblocking opens keep this wait bounded.
                deadline = time.monotonic() + 30
                while True:
                    try:
                        writer_fd = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
                        break
                    except OSError as error:
                        if error.errno != errno.ENXIO or process.poll() is not None:
                            raise
                        if time.monotonic() >= deadline:
                            raise RuntimeError("The application did not open the delayed input")
                        time.sleep(0.01)
                with os.fdopen(writer_fd, "wb", buffering=0) as writer:
                    raced.write_bytes(b"created by another process")
                    writer.write(b"delayed source")
                stdout, stderr = process.communicate(timeout=30)
                evidence["cases"].append({"case": "concurrent output preserved",
                                          "command": invocation, "exit": process.returncode,
                                          "stdout": stdout, "stderr": stderr})
                if process.returncode != 1 or raced.read_bytes() != b"created by another process":
                    raise RuntimeError("Exclusive output creation did not preserve a concurrent file")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
        if template_hashes(consumer) != hashes:
            raise RuntimeError("The copied template changed during file-tool verification")
        if digest(installed_pc) != installed_hash:
            raise RuntimeError("The upstream installed metadata was changed")
        evidence.update({"metadata_preserved": True, "template_preserved": True, "passed": True})
    except Exception as error:
        evidence["error"] = str(error)
        raise
    finally:
        save()
    print(f"Published 0.3.1 file tool: diagnostic repair, 4 interoperable file round trips "
          f"and file safety checks passed; {destination}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, StopIteration, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error))
