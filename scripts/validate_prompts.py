"""Lint the versioned LLM prompt config (LLMOps 'prompt as code' check)."""
import json
import re
import sys
from pathlib import Path

REQUIRED_CATEGORIES = {"billing", "technical", "account", "shipping"}
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")


def validate(cfg: dict) -> list:
    errors = []
    if not SEMVER.match(str(cfg.get("version", ""))):
        errors.append("version must be semver, e.g. 1.0.0")
    temp = cfg.get("temperature")
    if not isinstance(temp, (int, float)) or not 0 <= temp <= 1:
        errors.append("temperature must be a number between 0 and 1")
    if not cfg.get("model_alias"):
        errors.append("model_alias is required")
    templates = cfg.get("templates", {})
    missing = REQUIRED_CATEGORIES - set(templates)
    if missing:
        errors.append(f"missing templates: {sorted(missing)}")
    for name, text in {**templates, "fallback": cfg.get("fallback", "")}.items():
        if "{ticket}" not in text:
            errors.append(f"template '{name}' must contain the {{ticket}} placeholder")
    return errors


if __name__ == "__main__":
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent.parent / "prompts" / "triage_prompts.json"
    problems = validate(json.loads(path.read_text()))
    if problems:
        print("Prompt validation FAILED:")
        for p in problems:
            print(" -", p)
        sys.exit(1)
    print(f"Prompt config OK: {path}")
