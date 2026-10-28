# Perspective Opus for iPhone and iPad

The Apple build uses the same Godot 4.6 simulation, renderers, audio, touch input,
controller input, and local save data as the published Android game. The iOS
preset does not modify the Android presets or the recorded level solutions.

Bundle ID requested: `app.toyboxes.perspectiveopus`. Apple version 1.1.0, build 1.
The owner requested a USD 1.99 one-time download. This is not yet a registered
Apple app record or a saved Apple price.

## Build

Install Xcode and the official Godot 4.6 iOS export templates. Import the project
with the repository's Godot 4.6 executable, then run:

```sh
python3 tools/build_ios.py --unsigned
```

This exports the Xcode project and builds an unsigned ARM64 device app. Godot
requires a Team ID even for project-only export. The script temporarily supplies
an all-zero placeholder, restores the preset in a finally block, removes that
placeholder from the generated Xcode project, and disables signing. It never
signs to the existing Individual membership.

After Apple confirms the Randroid LLC organization membership, use:

```sh
python3 tools/build_ios.py --team VERIFIED_TEAM_ID
```

Open `build/ios/PerspectiveOpus.xcodeproj`, choose organization signing, archive,
validate, and upload using the verified account. Signing, provisioning, TestFlight,
App Store metadata, pricing, agreements, and review remain separate release steps.

## Device checks

An unsigned build proves compilation and packaging. It does not prove iPhone or
iPad runtime. Before submission, test both Score and Stage, the perspective
transition, simultaneous movement/jump, controller input, safe areas in both
landscape directions, pause/resume after backgrounding, local save restoration,
audio crossfades, and all six movements. Capture real Apple gameplay for the
store. Godot 4.6's documented iOS simulator support is limited; do not substitute
a macOS render for an iPhone screenshot.

The preset declares no tracking or collected data. Required-reason API values
cover app-container file timestamps, local elapsed time, and disk space for
on-device file writes. Review the generated privacy manifest with the exact
engine version and any future plugins before submission.

Apple organization verification is pending. The legal publisher remains Randroid LLC.


## Verification recorded October 21, 2026

- `tests/parity.gd`: all six movements finish with all seven notes, no deaths,
  and worst numeric drift below 3e-14.
- `python3 tools/build_ios.py --unsigned`: end-to-end export and Release ARM64
  device build passed, including a second clean export. The preset Team ID is
  blank again after the command.
- Generated app readback: `app.toyboxes.perspectiveopus`, version 1.1.0, build 1,
  device families iPhone and iPad, bundled game pack 82,602,564 bytes, and no
  embedded provisioning profile.
- The supplied 4.6 simulator archive contains x86_64 objects even though its
  xcframework metadata also advertises ARM64. Intel simulator compilation passes;
  ARM64 simulator linking fails on the missing entry point. No Apple-device
  runtime or simulator gameplay is claimed.

Local generated outputs are under `build/ios/`. The App Store text is prepared in
`docs/apple/en-US.json`; it has not been saved in App Store Connect.

## Simulator build on Apple Silicon

The installed official Godot 4.6 iOS template marks its simulator framework as
ARM64 and x86_64, but `lipo -info` reports that its `libgodot.a` contains only
x86_64 objects. An ARM64 simulator link cannot succeed with that archive.
After `python3 tools/build_ios.py --unsigned` generates the Xcode project, an
unsigned x86_64 simulator build can be compiled with:

```sh
xcodebuild -project build/ios/PerspectiveOpus.xcodeproj \
  -scheme PerspectiveOpus -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/ios/SimulatorIntel \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=NO build
```

This command builds the simulator app. Runtime playtesting remains a separate
check, and Apple Silicon may require Rosetta to run the x86_64 app.

## Verification recorded October 28, 2026

- At source commit `6e854c28a005b08b7ae4e87e492d97cf426b203e`, the
  unsigned x86_64 iOS Simulator Release build passed with Xcode 27.0. The app
  identifies as `app.toyboxes.perspectiveopus`, version 1.1.0, build 1.
- Fresh headless parity passed all six movements with seven notes and zero deaths
  each; worst numeric drift was 2.84e-14.
- Local headless input flow passed 42 of 42 checks, and the six-movement campaign
  replay passed 25 of 25 checks, including all 42 notes and the ending. These
  were macOS Godot runs, not iOS runtime checks.
