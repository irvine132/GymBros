#!/usr/bin/env python3
"""Compare the packaged DEX methods to Pigeon JNI getAll descriptors.

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


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: python3 scripts/check_jni_descriptors.py APK ANDROID_SDK_ROOT", file=sys.stderr)
        return 2
    apk = pathlib.Path(sys.argv[1])
    dexdump = pathlib.Path(sys.argv[2]) / "build-tools/36.0.0/dexdump"
    if not dexdump.is_file():
        print(f"DEX tool unavailable: {dexdump}", file=sys.stderr)
        return 2
    with zipfile.ZipFile(apk) as archive, tempfile.TemporaryDirectory() as directory:
        dex = pathlib.Path(directory) / "classes.dex"
        dex.write_bytes(archive.read("classes.dex"))
        output = subprocess.run(
            [str(dexdump), "-f", str(dex)], check=True, capture_output=True, text=True
        ).stdout
    classes = re.split(r"(?=^Class #\d+\s+-)", output, flags=re.MULTILINE)
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
        prefix = f"Lio/flutter/plugins/sharedpreferences/{cls};"
        block = next((part for part in classes if f"Class descriptor  : '{prefix}'" in part), "")
        actual = re.findall(r"name\s+: 'getAll'\s+type\s+: '([^']+)'", block)
        print(f"{cls}.getAll: expected={expected} packaged={actual}")
        if expected not in actual:
            failures.append(cls)
    if failures:
        print(f"JNI DEX descriptor mismatch: {', '.join(failures)}", file=sys.stderr)
        return 1
    print("JNI DEX getAll descriptors match generated Dart calls")
    return 0


if __name__ == "__main__":
    sys.exit(main())
