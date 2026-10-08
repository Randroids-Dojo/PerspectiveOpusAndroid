#!/usr/bin/env python3
"""Build signed Android releases using credentials kept outside the repository."""

import argparse
import os
from pathlib import Path
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preset", choices=("Android", "Google Play"))
    parser.add_argument("--godot", default=os.environ.get(
        "GODOT", str(Path.home() / "Applications/Godot-4.6/Godot.app/Contents/MacOS/Godot")))
    parser.add_argument("--keystore", type=Path,
                        default=Path.home() / ".config/perspectiveopus/upload.keystore")
    parser.add_argument("--password-file", type=Path,
                        default=Path.home() / ".config/perspectiveopus/upload.pass")
    parser.add_argument("--alias", default="upload")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if not args.keystore.is_file() or not args.password_file.is_file():
        parser.error("Release keystore or password file is missing.")
    opus_sign_env = dict(os.environ)
    opus_sign_env["GODOT_ANDROID_KEYSTORE_RELEASE_PATH"] = str(args.keystore.resolve())
    opus_sign_env["GODOT_ANDROID_KEYSTORE_RELEASE_USER"] = args.alias
    opus_sign_env["GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"] = args.password_file.read_text().strip()
    (root / "build").mkdir(exist_ok=True)
    builds = [("Android", "apk"), ("Google Play", "aab")]
    for preset, extension in builds:
        if args.preset and preset != args.preset:
            continue
        output = root / "build" / f"PerspectiveOpus.{extension}"
        log = Path(f"/tmp/opus-export-{extension}-release.log")
        with log.open("w") as stream:
            result = subprocess.run(
                [args.godot, "--headless", "--path", str(root),
                 "--export-release", preset, str(output)],
                cwd=root, env=opus_sign_env, stdout=stream, stderr=subprocess.STDOUT)
        if result.returncode:
            print(f"{preset} export failed. See {log}.", file=sys.stderr)
            return result.returncode
        print(f"Built {output} ({output.stat().st_size / 1048576:.1f} MiB). Log: {log}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
