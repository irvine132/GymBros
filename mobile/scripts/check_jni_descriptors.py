#!/usr/bin/env python3
"""Check packaged DEX against the Pigeon and Kotlin JNI startup contract.

Usage: python3 scripts/check_jni_descriptors.py APK ANDROID_SDK_ROOT
"""

import json
import pathlib
import re
import subprocess
import sys
import tempfile
import zipfile
from urllib.parse import unquote, urlparse


APIS = (
    ("SharedPreferencesApiRegistrar", "messages.g.jni.dart"),
    ("SharedPreferencesAsyncApiRegistrar", "messages_async.g.jni.dart"),
)

# Literal lookups in jni 1.1.0 kotlin.dart (not inferred from Kotlin call sites).
KOTLIN_CLASSES = (
    "kotlin/coroutines/Continuation",
    "kotlin/coroutines/intrinsics/CoroutineSingletons",
    "kotlin/Result",
    "kotlin/Result$Failure",
    "kotlin/coroutines/intrinsics/IntrinsicsKt",
    "kotlin/Unit",
)
FIELDS = (
    ("kotlin/Result", "value", "Ljava/lang/Object;", False),
    ("kotlin/Result$Failure", "exception", "Ljava/lang/Throwable;", False),
    ("kotlin/Unit", "INSTANCE", "Lkotlin/Unit;", True),
)
METHODS = (
    ("kotlin/coroutines/Continuation", "resumeWith", "(Ljava/lang/Object;)V", False),
    ("kotlin/Result$Failure", "<init>", "(Ljava/lang/Throwable;)V", False),
    ("kotlin/coroutines/intrinsics/IntrinsicsKt", "getCOROUTINE_SUSPENDED", "()Ljava/lang/Object;", True),
)


def dex_classes(output: str) -> dict[str, str]:
    """Split -f class definitions, not references in the DEX string pool."""
    blocks = re.split(r"(?=^Class #\d+\s+-)", output, flags=re.MULTILINE)
    result = {}
    for block in blocks:
        match = re.search(r"^  Class descriptor  : 'L([^']+);'$", block, re.MULTILINE)
        if match:
            if match.group(1) in result:
                raise ValueError(f"Duplicate DEX class: {match.group(1)}")
            result[match.group(1)] = block
    return result


def members(block: str, section: str):
    """Yield declared name, descriptor, static flag within one DEX section."""
    parts = re.split(r"^  (?:Static fields|Instance fields|Direct methods|Virtual methods)\s+-\s*$", block, flags=re.MULTILINE)
    headings = re.findall(r"^  (Static fields|Instance fields|Direct methods|Virtual methods)\s+-\s*$", block, flags=re.MULTILINE)
    for heading, body in zip(headings, parts[1:]):
        if heading != section:
            continue
        for member in re.split(r"(?=^    #\d+\s+:)", body, flags=re.MULTILINE)[1:]:
            name = re.search(r"^      name\s+: '([^']+)'$", member, re.MULTILINE)
            descriptor = re.search(r"^      type\s+: '([^']+)'$", member, re.MULTILINE)
            access = re.search(r"^      access\s+: 0x([0-9a-f]+)", member, re.MULTILINE)
            if name and descriptor and access:
                yield name.group(1), descriptor.group(1), bool(int(access.group(1), 16) & 0x8)


def resolves(classes: dict[str, str], owner: str, name: str, descriptor: str, static: bool, method: bool) -> bool:
    """JNI method/field lookup may resolve a member on a superclass."""
    seen = set()
    while owner in classes and owner not in seen:
        seen.add(owner)
        block = classes[owner]
        sections = ("Direct methods", "Virtual methods") if method else ("Static fields", "Instance fields")
        if any((name, descriptor, static) in members(block, section) for section in sections):
            return True
        parent = re.search(r"^  Superclass\s+: 'L([^']+);'$", block, re.MULTILINE)
        owner = parent.group(1) if parent else ""
    return False


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: python3 scripts/check_jni_descriptors.py APK ANDROID_SDK_ROOT", file=sys.stderr)
        return 2
    apk = pathlib.Path(sys.argv[1])
    dexdump = pathlib.Path(sys.argv[2]) / "build-tools/36.0.0/dexdump"
    if not dexdump.is_file():
        print(f"DEX tool unavailable: {dexdump}", file=sys.stderr)
        return 2
    classes = {}
    with zipfile.ZipFile(apk) as archive, tempfile.TemporaryDirectory() as directory:
        dex_names = sorted(n for n in archive.namelist() if re.fullmatch(r"classes(?:\d+)?\.dex", n))
        if not dex_names:
            raise ValueError("APK has no classes*.dex")
        for dex_name in dex_names:
            dex = pathlib.Path(directory) / dex_name
            dex.write_bytes(archive.read(dex_name))
            output = subprocess.run(
                [str(dexdump), "-f", str(dex)], check=True, capture_output=True, text=True
            ).stdout
            for name, block in dex_classes(output).items():
                if name in classes:
                    raise ValueError(f"Duplicate DEX class across files: {name}")
                classes[name] = block
    print(f"Inspected {len(dex_names)} DEX file(s), {len(classes)} class definitions")
    config = json.loads((pathlib.Path(__file__).resolve().parent.parent / ".dart_tool/package_config.json").read_text())
    package = next(p for p in config["packages"] if p["name"] == "shared_preferences_android")
    uri = package["rootUri"]
    parsed = urlparse(uri)
    plugin = pathlib.Path(unquote(parsed.path)) if parsed.scheme == "file" else (
        pathlib.Path(__file__).resolve().parent.parent / ".dart_tool" / uri
    ).resolve()
    failures = []
    for cls, filename in APIS:
        source = (plugin / "lib/src" / filename).read_text()
        match = re.search(r"r'getAll',\s*r'([^']+)'", source)
        if match is None:
            raise ValueError(f"Missing generated JNI getAll descriptor in {filename}")
        expected = match.group(1)
        block = classes.get(f"io/flutter/plugins/sharedpreferences/{cls}", "")
        actual = [descriptor for name, descriptor, _ in members(block, "Virtual methods") if name == "getAll"]
        print(f"{cls}.getAll: expected={expected} packaged={actual}")
        if expected not in actual:
            failures.append(cls)
    for owner in KOTLIN_CLASSES:
        if owner not in classes:
            failures.append(f"missing class {owner}")
    for owner, name, descriptor, static in FIELDS:
        if not resolves(classes, owner, name, descriptor, static, False):
            failures.append(f"missing field {owner}.{name}:{descriptor} static={static}")
    for owner, name, descriptor, static in METHODS:
        if not resolves(classes, owner, name, descriptor, static, True):
            failures.append(f"missing method {owner}.{name}{descriptor} static={static}")
    if failures:
        print(f"JNI DEX descriptor mismatch: {', '.join(failures)}", file=sys.stderr)
        return 1
    print("JNI DEX getAll and Kotlin bootstrap classes/members resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
