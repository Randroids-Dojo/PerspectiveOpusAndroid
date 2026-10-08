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
| Pixel 8 Pro exported flow | 42 checks pass at normal speed on Android 17, Vulkan 1.4.343, Mali-G715 and Forward Mobile |
| Pixel 8 Pro full campaign | 25 checks pass at normal speed; six movements, 42 saved notes, zero deaths, 21 switches, ending and return to title |
| Native full campaign | 25 checks pass; six movements, 42 saved notes, zero deaths, ending and return to title |
| Native shutdown | Flow, campaign and windowed screenshot exit without script errors or leaked resources |
| Native presentation | All palettes and both switch directions compared against the web build; night Score with touch HUD inspected after integration |
| Audio assets | 736 files, 49.09 MiB; manifest references and exact frame lengths checked |
| Audio mix | 28 steady conditions within 0.2 dB of the web reference; no clipping or dropped sounds; synchronized stems and clean loop wraps |
| Android packages | Signed APK and AAB, version 1.1.0 code 2, arm64; all 736 imported audio streams included; APK passes 16 KiB alignment |

The campaign replay feeds the web's 120 Hz action recordings through the native simulation and director. Desktop checks use increased speed; the exported Pixel campaign ran at normal speed. Separate flow checks use normal-speed keyboard, touch, controller and Android back events. Flow tests teleport to a pickup and exit for persistence and menu checks; the full campaign does not teleport.

Release APK: 94.4 MiB, targets API 35. Play AAB: 89.7 MiB, targets API 36 through the Gradle export. Both were rebuilt with the terrain preparation change from commit `a10e18f`. They use the existing upload certificate; the APK signature, 16 KiB archive alignment and the AAB JAR signature verify. All 736 imported audio streams and eight scores are included. During world switches the native reverb differs from the web reference by up to 3.2 dB, typically 1 to 2 dB. Physical Android listening and actual touch-to-sound latency remain unverified.

Evidence from this run:

- `/tmp/opus-native-polish-flow-release.log`
- `/tmp/opus-native-polish-campaign-release.log`
- `/tmp/opus-native-polish-parity.log`
- `/tmp/opus-native-polish-night.png`
- `/tmp/stage-compare/`
- `/tmp/score_report/`

## Android check limits

The Pixel 8 Pro connected through wireless ADB and ran the exported self-test on its actual Mobile renderer. All 42 flow checks passed at normal speed in 26.9 seconds, with no script errors, fatal exceptions or shutdown leaks in the captured process log. These checks inject keyboard, controller, multitouch and back events through the native engine. They do not establish physical Bluetooth controller behavior or OS-level touch/back handling.

The exported full campaign then passed all 25 checks on the same phone at normal speed, with all 42 notes saved, zero deaths and 21 world switches. It reached the ending, credits and title. The captured process log contains no script errors, fatal exceptions or shutdown warnings. The preserved JSON receipt is [the Pixel campaign report](qa/pixel-8-pro-2026-10-08.json).

The signed regular release was installed in the primary profile and its title inspected at 2244x1008. An OS-level Begin tap also reached playable Overture. A PiP video was present during this release check, and YouTube subsequently became the foreground. The input guard stopped further commands. Screenshots containing that overlay and the earlier interrupted playback recording were discarded. OS-level world switching/back and game-only playback capture remain pending.

The campaign collected 28 frame groups at medium quality, with the automatic detail tier disabled and the Stage resolution governor active. Gameplay averages, including transition and level-load outliers, were 52.1 fps on the Stage and 52.4 fps on the Score. The ink-wipe portions averaged 29.4 fps; Page CPU cost peaked at 237.6 ms during a switch. Level-load frames reached 1.0 second. These results do not establish a steady 60 fps result. Video activity during the campaign was not recorded, so this is a device-session measurement rather than an isolated performance benchmark. No screenshots or screen recordings ran during the campaign.

The native audio driver delivered 15,758,694 frames before clean shutdown. Audio diagnostics reported zero dropped sounds and 52 trimmed old tails across 2,531 effects. Physical speaker listening and actual touch-to-sound latency remain unverified; the engine's zero-valued output-latency field is not a measurement of zero hardware latency.

The first-use Score hitch led to a renderer change: paint its initial terrain during level preparation, then spend a small background budget maintaining the visible terrain and neighbouring chunks while on the Stage. Chunk geometry is released only after a render-frame completion signal, so preparation cannot clear a drawing before the GPU has seen it. Day and night switch screenshots show the complete cached terrain, and the updated local flow and full campaign checks pass. The timing improvement from this change still needs a new phone run.

Desktop performance measurements are not phone estimates. The Stage and page both use quality scaling.

The test-only profiler records frame intervals by movement, world, director state and quality, along with Page CPU cost, Stage resolution scale and audio diagnostics. One accelerated desktop profiling run emitted an ObjectDB shutdown warning; its verbose follow-up completed all 25 checks and exited cleanly. The exported phone flow also exited cleanly.

Wireless evidence:

- `/tmp/opus-pixel-flow.log`
- `/tmp/opus-pixel-release-title.png`
- `/tmp/opus-pixel-campaign.log`
- `/tmp/opus-pixel-campaign-report.json`
- `/tmp/opus-device-profile-harness.log`
- `/tmp/opus-profile-full-verbose.log`
- `/tmp/opus-prewarm-flow-final.log`
- `/tmp/opus-prewarm-full.log`
- `/tmp/opus-prewarm-rendered-campaign.log`
- `/tmp/opus-prewarm-switch.png`
- `/tmp/opus-prewarm-nocturne.png`

The Android emulator launched the exported Mobile renderer but hung at a Vulkan `QueuePresentKHR` failure before the title or flow checks. Both software Vulkan and MoltenVK were tried. A related Godot emulator issue is recorded at https://github.com/godotengine/godot/issues/105598. The test package was removed, the temporary storage threshold restored, and the emulator stopped. The production build keeps the required Mobile renderer.

## Repeating the checks

```sh
GODOT=~/Applications/Godot-4.6/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path . --import
$GODOT --headless --path . --script tests/parity.gd
$GODOT --headless --path . -- --selftest=flow
$GODOT --headless --path . -- --selftest=full --speed=8
$GODOT --headless --path . -- --selftest=full --speed=8 --profile
$GODOT --headless --path . --script src/audio/dev/check.gd
$GODOT --path . -- --level=nocturne --mode=2d --device=touch --shot=/tmp/opus-night.png --frames=120
$GODOT --headless --path . --export-debug "Android Selftest" build/PerspectiveOpus-selftest.apk
python3 tools/build_android.py
```

The Android Selftest preset has a separate package ID and includes the six recorded solutions. It automatically runs the flow checks unless its app-private `selftest_config.json` selects the full campaign. The shipping game ignores this file. The self-test does not touch the regular game's save.

On an awake, unlocked and available device with video playback and PiP closed, connect wireless ADB using its current debugging address, then run:

```sh
~/Library/Android/sdk/platform-tools/adb connect <wireless-address:port>
python3 tools/check_android.py --serial <wireless-address:port> --install --mode full --profile
```

The runner installs the existing self-test APK, writes its app-private configuration and collects a process log and JSON receipt. It stops its own QA package if the device foreground changes or PiP starts. Full replay runs at normal speed by default, with no teleporting. Its quality stays at the phone's initial medium tier while the Stage resolution governor remains active; the shipping automatic tier governor is disabled during self-tests. Record cold-load outliers separately when interpreting the frame report.

`build_android.py` reads the existing upload key and password file from `~/.config/perspectiveopus/`, passes them to Godot through its signing environment variables, and builds the APK and AAB in sequence. Release outputs belong in `build/` and stay out of Git. Keystores and signing credentials also stay out of Git.
