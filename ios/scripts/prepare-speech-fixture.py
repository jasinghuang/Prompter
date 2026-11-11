#!/usr/bin/env python3
"""Prepare hash-pinned weights; the Swift manifest supplies sources and hashes."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import urllib.request
import uuid

IOS = Path(__file__).resolve().parents[1]


def checksum(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            result.update(chunk)
    return result.hexdigest()


def verify(path, size, digest):
    if path.stat().st_size != size:
        raise RuntimeError(f"Incorrect file size: {path.name}")
    if digest and checksum(path) != digest:
        raise RuntimeError(f"Checksum mismatch: {path.name}")


def download_verified(target, size, digest, sources, open_url=urllib.request.urlopen):
    """Only replace a model after verification, even when a mirror changes."""
    errors = []
    for source in sources:
        temporary = target.with_name(f"{target.name}.{uuid.uuid4().hex}.partial")
        try:
            print(f"Downloading {target.name} from {source}", flush=True)
            with open_url(source, timeout=20) as response, temporary.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            verify(temporary, size, digest)
            temporary.replace(target)
            return
        except Exception as error:
            errors.append(str(error))
            print(f"Source failed: {error}; trying next source", flush=True)
        finally:
            temporary.unlink(missing_ok=True)
    raise RuntimeError(f"All model sources failed for {target.name}: {'; '.join(errors)}")


def prepare(bundle):
    manifest = (IOS / "Prompter/Services/SpeechModelStore.swift").read_text()
    revision = re.search(r'static let revision = "([a-f0-9]+)"', manifest).group(1)
    source_block = re.search(r'static let downloadBases = \[([^\]]+)\]', manifest).group(1)
    bases = re.findall(r'"(https://[^"]+)"', source_block)
    assets = re.findall(r'\.init\(name: "([^"]+)", bytes: ([\d_]+),\s*sha256: "([a-f0-9]+)"', manifest)
    fixture = IOS / "build/speech-fixture"
    resources = IOS / "Prompter/Resources/ParaformerModel"
    destination = resources if bundle else fixture
    destination.mkdir(parents=True, exist_ok=True)
    for name, size, digest in assets + ([] if bundle else [("test.wav", "321744", "")]):
        size = int(size.replace("_", ""))
        target = destination / name
        if target.is_file():
            try:
                verify(target, size, digest)
                print(f"Verified {name}", flush=True)
                continue
            except RuntimeError:
                pass
        cached = (fixture if bundle else resources) / name
        if cached.is_file():
            try:
                verify(cached, size, digest)
                temporary = target.with_name(f"{name}.{uuid.uuid4().hex}.partial")
                try:
                    print(f"Using verified local model: {name}", flush=True)
                    shutil.copyfile(cached, temporary)
                    temporary.replace(target)
                finally:
                    temporary.unlink(missing_ok=True)
                continue
            except RuntimeError:
                pass
        sources = [f"{bases[-1]}/test_wavs/0.wav"] if name == "test.wav" else [f"{base}/{name}" for base in bases]
        download_verified(target, size, digest, sources)
    (destination / "verified").write_text(revision)
    print(f"Offline speech {'bundle' if bundle else 'fixture'} ready: {destination}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", action="store_true", help="prepare app resources without test audio")
    prepare(parser.parse_args().bundle)
