#!/usr/bin/env python3
"""Export the shared native game to Xcode without selecting a publisher by accident."""

import argparse
import os
import plistlib
from pathlib import Path
import re
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--team", help="The verified organization Apple Team ID")
    choice.add_argument("--unsigned", action="store_true", help="Local build only, with signing disabled")
    parser.add_argument("--godot", default=os.environ.get(
        "GODOT", str(Path.home() / "Applications/Godot-4.6/Godot.app/Contents/MacOS/Godot")))
    args = parser.parse_args()
    if args.team and not re.fullmatch(r"[A-Z0-9]{10}", args.team):
        parser.error("Apple Team ID must contain 10 uppercase letters or digits.")
    root = Path(__file__).resolve().parent.parent
    presets = root / "export_presets.cfg"
    original = presets.read_text()
    # Godot requires a nonempty Team ID even for project-only export. The all-zero
    # value is a local export placeholder. It is removed from the generated Xcode
    # project before any unsigned build and is never a release signing identity.
    team = args.team or "0000000000"
    marker = 'application/app_store_team_id=""'
    if original.count(marker) != 1:
        parser.error("Expected exactly one unconfigured iOS Team ID in the preset.")
    output = root / "build" / "ios"
    output.mkdir(parents=True, exist_ok=True)
    try:
        presets.write_text(original.replace(marker, f'application/app_store_team_id="{team}"'))
        subprocess.run([args.godot, "--headless", "--path", str(root), "--export-release",
                        "iOS", str(output / "PerspectiveOpus.zip")], cwd=root, check=True)
    finally:
        presets.write_text(original)
    project = output / "PerspectiveOpus.xcodeproj" / "project.pbxproj"
    info = output / "PerspectiveOpus" / "PerspectiveOpus-Info.plist"
    properties = plistlib.loads(info.read_bytes())
    # The template supplies empty permission strings for APIs this game never uses.
    for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription"):
        if not properties.get(key):
            properties.pop(key, None)
    info.write_bytes(plistlib.dumps(properties))
    if args.unsigned:
        project.write_text(re.sub(rf"(\b(?:DEVELOPMENT_TEAM|DevelopmentTeam)\s*=\s*)\"?{team}\"?;",
                                  r'\1"";', project.read_text()))
        subprocess.run(["xcodebuild", "-project", str(project.parent), "-scheme", "PerspectiveOpus",
                        "-configuration", "Release", "-sdk", "iphoneos", "-destination",
                        "generic/platform=iOS", "-derivedDataPath", str(output / "DerivedData"),
                        "CODE_SIGNING_ALLOWED=NO", "DEVELOPMENT_TEAM=", "build"], cwd=root, check=True)
    print(f"Xcode project: {project.parent}")
    print("Local unsigned build only." if args.unsigned else "Organization Team ID configured; archive and upload separately.")


if __name__ == "__main__":
    main()
