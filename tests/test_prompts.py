import json
from pathlib import Path
from validate_prompts import validate

CFG = Path(__file__).parent.parent / "prompts" / "triage_prompts.json"


def test_shipped_prompts_are_valid():
    assert validate(json.loads(CFG.read_text())) == []


def test_missing_placeholder_is_caught():
    cfg = json.loads(CFG.read_text())
    cfg["templates"]["billing"] = "no placeholder here"
    assert any("billing" in e for e in validate(cfg))
