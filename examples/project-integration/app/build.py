"""Experimental MoonBit prebuild entry; never invokes moon or a shell."""

import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from adapter import DEPENDENCY, plan


def main():
    project = Path(__file__).resolve().parent
    request = json.load(sys.stdin)
    if Path(request["paths"]["module_root"]).resolve() != project:
        raise ValueError("Unexpected prebuild module root")
    report = project / "_build/native-plan.json"
    report.parent.mkdir(exist_ok=True)
    evidence = {"dependency": DEPENDENCY, "passed": False}
    report.write_text(json.dumps(evidence) + "\n", encoding="utf-8")
    try:
        configured = json.loads((project / "_build/native-config.json").read_text(encoding="utf-8"))
        if not configured.get("configured"):
            raise ValueError("Run configure.py before building the application")
        output, plans = plan(project, configured)
        evidence.update({"passed": True, "plans": plans, "output": output})
        print(json.dumps(output))
    except Exception as error:
        evidence["error"] = str(error)
        raise
    finally:
        report.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
