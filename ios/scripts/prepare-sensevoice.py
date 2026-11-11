#!/usr/bin/env python3
"""Bundle a pinned comparison model, without requiring phone downloads."""
import hashlib
import importlib.util
import json
import shutil
import tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("speech_assets", HERE / "prepare-speech-fixture.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
manifest = json.loads((HERE / "sensevoice-model.json").read_text())
root = HERE.parent / "Prompter/Resources/SenseVoiceModel"
root.mkdir(parents=True, exist_ok=True)
missing = []
for asset in manifest["files"]:
    try:
        helpers.verify(root / asset["name"], asset["bytes"], asset["sha256"])
    except (OSError, RuntimeError):
        missing.append(asset)
if missing:
    archive = HERE.parent / "build/speech-extra-cache" / manifest["archive"]
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists() or helpers.checksum(archive) != manifest["archive_sha256"]:
        temporary = archive.with_suffix(".download")
        try:
            with helpers.urllib.request.urlopen(manifest["url"], timeout=30) as source, temporary.open("wb") as target:
                shutil.copyfileobj(source, target)
            if helpers.checksum(temporary) != manifest["archive_sha256"]:
                raise RuntimeError("SenseVoice archive checksum mismatch")
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    with tarfile.open(archive) as tar:
        for asset in missing:
            member = next(x for x in tar.getmembers() if Path(x.name).name == asset["name"] and x.isfile())
            temporary = root / (asset["name"] + ".partial")
            try:
                with tar.extractfile(member) as source, temporary.open("wb") as target:
                    shutil.copyfileobj(source, target)
                helpers.verify(temporary, asset["bytes"], asset["sha256"])
                temporary.replace(root / asset["name"])
            finally:
                temporary.unlink(missing_ok=True)
(root / "verified").write_text(manifest["revision"])
print("Offline SenseVoice comparison model ready", flush=True)
