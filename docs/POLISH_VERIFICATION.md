# Polish verification

Checked on 8 October 2026 for version 1.1.0, Android version code 2.

The native game now draws the web build's illuminated Score and lit Stage, including every movement palette, prop, entity and ink wipe. Generated textures, Stage meshes and music come from the web build's own generators. A thin gold landing cue follows the surface below Quaver in either world, including moving stands and drums. The Stage's frustum camera preserves the side view's scale during a switch.

The HUD gives an explicit note count and recovery notices. The touch switch names its destination, while the HUD badge names the current world. Nocturne uses silver ink and gold accents on indigo plates. Movement cards clear after 2.8 seconds. Reduced motion removes pickup flights, card travel, badge pulses and idle camera orbits. Each pickup is saved immediately.

Held controller triggers switch once per press and select controller hints. Losing focus clears held input and suspends polling; focus return restores input. Releasing the movement finger preserves another finger's held jump. Pause, keyboard Escape, controller back and the Android back gesture each perform one action.

Music uses synchronized Score and Stage arrangements, restored-note layers, equal-power crossfades, and the original room and hall recordings. Effects follow the current harmony. Audio includes ambience, menu filtering, switch swells and the master compressor and limiter. Shutdown waits for the audio server to release stopped playbacks.

## Verified results

| Check | Result |
| --- | --- |
| Simulation parity | All six web recordings finish with seven notes and zero deaths; maximum position drift below 3e-14 |
| Native input and UI flow | 42 checks pass, including focus recovery, independent touch contacts, held triggers, pause/back and pickup persistence |
| Native full campaign | 25 checks pass; six movements, 42 saved notes, zero deaths, ending and return to title |
| Native shutdown | Flow, campaign and windowed screenshot exit without script errors or leaked resources |
| Native presentation | All palettes and both switch directions compared against the web build; night Score with touch HUD inspected after integration |
| Audio assets | 736 files, 49.09 MiB; manifest references and exact frame lengths checked |
| Audio mix | 28 steady conditions within 0.2 dB of the web reference; no clipping or dropped sounds; synchronized stems and clean loop wraps |
| Android packages | Signed APK and AAB, version 1.1.0 code 2, arm64; all 736 imported audio streams included; APK passes 16 KiB alignment |

The campaign replay feeds the web's 120 Hz action recordings through the native simulation and director at increased speed. Separate flow checks use normal-speed keyboard, touch, controller and Android back events. Flow tests teleport to a pickup and exit for persistence and menu checks; the full campaign does not teleport.

Release APK: 94.3 MiB, targets API 35. Play AAB: 89.7 MiB, targets API 36 through the Gradle export. Both use the existing upload certificate. The APK signature and the AAB JAR signature verify. During world switches the native reverb differs from the web reference by up to 3.2 dB, typically 1 to 2 dB. Physical Android audio output and latency remain unverified.

Evidence from this run:

- `/tmp/opus-native-polish-flow-release.log`
- `/tmp/opus-native-polish-campaign-release.log`
- `/tmp/opus-native-polish-parity.log`
- `/tmp/opus-native-polish-night.png`
- `/tmp/stage-compare/`
- `/tmp/score_report/`

## Android check limits

The connected Pixel 8 Pro was asleep and locked. Phone frame time, first-use shader hitches and physical listening are unverified. Desktop performance measurements are not phone estimates. The Score's initial visible chunk paint takes about 90 to 125 ms on this Mac; the Stage and page both use quality scaling.

The Android emulator launched the exported Mobile renderer but hung at a Vulkan `QueuePresentKHR` failure before the title or flow checks. Both software Vulkan and MoltenVK were tried. A related Godot emulator issue is recorded at https://github.com/godotengine/godot/issues/105598. The test package was removed, the temporary storage threshold restored, and the emulator stopped. The production build keeps the required Mobile renderer.

## Repeating the checks

```sh
GODOT=~/Applications/Godot-4.6/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path . --import
$GODOT --headless --path . --script tests/parity.gd
$GODOT --headless --path . -- --selftest=flow
$GODOT --headless --path . -- --selftest=full --speed=8
$GODOT --headless --path . --script src/audio/dev/check.gd
$GODOT --path . -- --level=nocturne --mode=2d --device=touch --shot=/tmp/opus-night.png --frames=120
$GODOT --headless --path . --export-debug "Android Selftest" build/PerspectiveOpus-selftest.apk
python3 tools/build_android.py
```

The Android Selftest preset has a separate package ID and automatically runs the flow checks. It does not touch the regular game's save. `build_android.py` reads the existing upload key and password file from `~/.config/perspectiveopus/`, passes them to Godot through its signing environment variables, and builds the APK and AAB in sequence. Release outputs belong in `build/` and stay out of Git. Keystores and signing credentials also stay out of Git.
