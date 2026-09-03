#!/usr/bin/env python3
"""Freeze the MCOtxt v1 model manifest after the model set is finalized."""
from __future__ import annotations
import json
from pathlib import Path


def find_root() -> Path:
    here = Path(__file__).resolve()
    for candidate in (here.parent, *here.parents):
        if (candidate / "pubspec.yaml").is_file():
            return candidate
    for candidate in (Path.cwd().resolve(), *Path.cwd().resolve().parents):
        if (candidate / "lib" / "MCOtxt" / "models" / "mcotxt_model_registry.dart").is_file():
            return candidate
    raise SystemExit("Cannot locate project root")


def main() -> int:
    root = find_root()
    path = root / "tools" / "MCOtxt" / "generated" / "model_manifest.json"
    if not path.is_file():
        raise SystemExit(f"Model manifest not found: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    unavailable = [code.upper() for code, entry in data.get("models", {}).items() if not entry.get("available")]
    if unavailable:
        raise SystemExit("Refusing to freeze while models are unavailable: " + ", ".join(unavailable))
    data["frozen"] = True
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Frozen MCOtxt v{data.get('codecVersion')} model manifest: {path}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
