#!/usr/bin/env python3
"""Prepare the shared VAD, with pinned size/hash and atomic installation."""
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("speech_assets", HERE / "prepare-speech-fixture.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
root = HERE.parent / "Prompter/Resources/SpeechSupport"
root.mkdir(parents=True, exist_ok=True)
for asset in json.loads((HERE / "speech-support.json").read_text())["assets"]:
    target = root / asset["name"]
    try:
        helpers.verify(target, asset["bytes"], asset["sha256"])
    except (OSError, RuntimeError):
        helpers.download_verified(target, asset["bytes"], asset["sha256"], asset["sources"])
print("Shared offline speech detector ready", flush=True)
