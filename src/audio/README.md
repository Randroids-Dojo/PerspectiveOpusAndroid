# Audio

The web build makes every sound live in Web Audio. Here the same engine is run offline once, in Chrome, and its output is played back natively. `audio.gd` (the `Audio` node in `main.tscn`, class `OpusAudio`) keeps the web build's interface and behaviour.

## Making the files

```sh
../PerspectiveOpus/node_modules/.bin/tsx tools/render_audio.ts                 # everything, about 3 minutes
../PerspectiveOpus/node_modules/.bin/tsx tools/render_audio.ts --only=music --songs=finale
../PerspectiveOpus/node_modules/.bin/tsx tools/render_audio.ts --only=sfx      # or amb; --keep-raw keeps /tmp/opus-port-audio
$GODOT --headless --path . --import
```

`tools/render_audio.ts` starts Vite on the web repo, loads `tools/audio/harness.ts` in headless Chrome and drives the web build's own songs, players, mixer, rooms, instruments and effects through `OfflineAudioContext`s. `tools/audio/encode.py` encodes Ogg Vorbis with libvorbis (through libsndfile in a throwaway `uv` environment; Homebrew's ffmpeg only has the experimental native Vorbis encoder) and decodes every file again to check its length and loop seam. Everything is 32 kHz (the instruments themselves are rendered at 22 to 32 kHz).

`assets/audio/audio.json` describes it all: songs (stems, frames, loop point, tempo maps and chord timelines), the harmonies, the effect recipes, the voices and one-shots they play, the ambience beds and events, and the web desk's measured master chain.

| What | Files | Size |
| --- | --- | --- |
| Music stems, stereo, `music/<song>/<arr>_<layer>.ogg` | 92 | 39.3 MB |
| Notes the effects play (with their room or hall), `notes/` | 485 | 8.1 MB |
| One-shot effects (steps by material, jumps, page turns...), `sfx/` | 128 | 1.6 MB |
| Ambience beds and events, `amb/` | 31 | 1.6 MB |

### Music

One stem per song, arrangement (score, stage) and restore layer (tracks are grouped by the note count that brings them in, 0 to 7); the title and the ending are always full, so they have one stem per arrangement. Each stem is one contiguous slice of the song's timeline: the intro (title, finale), the first 8 s of the body, then exactly one body length. The loop starts 8 s into the body, where the previous pass's tails have died away, so the first time through starts clean (as on the web) and the loop repeats seamlessly; a 30 ms crossfade at the wrap hides the sub-sample difference between the song's length and a whole number of samples. Every stem of a song has the same length and loop point, and one `AudioStreamSynchronized` plays them all, so they cannot drift. The ending plays once.

### Effects

Tonal effects depend on the harmony sounding when they play. The tool runs the web build's `Sfx` class against every harmony the songs use (93, including each key's tonic for when the music has stopped) and records what it plays as recipes: notes, one-shot samples, music ducks, with their times. The notes (384 distinct, by instrument, pitch, length and attack skip) are rendered once each, exactly as the web's voice pool plays them, through the bus they play on (the page's room, the stage's hall, the menus' room). Footsteps, jumps, landings and bonks are one-shots with the web build's random variants and rates. Every effect file starts with 60 ms of silence: the engine starts a sound up to 60 ms early and skips into that silence, so notes land exactly where the recipe puts them, between frames.

## The engine

```gdscript
audio.unlock()                          # no-op on Android, kept for the shared interface
audio.set_perspective(blend)            # 0 score .. 1 stage, every frame (app.gd)
audio.set_time_scale(s)                 # every frame (app.gd): the switch swell
audio.handle(events, game)              # this frame's simulation events (app.gd)
audio.beat() -> float                   # music position in beats as heard, -1 when silent
audio.play_song(id)                     # title, overture, adagio, scherzo, nocturne, toccata, finale, ending
audio.stop_song(fade = 1.5)
audio.preload_song(id)                  # loads a song's stems in the background (`preload` is a GDScript keyword)
audio.set_restored(found, total)        # layers fade in as notes are found
audio.ui(name)                          # hover, confirm, back, pause, resume, start, complete, unlock, page
audio.set_volumes(master, music, sfx)   # or set_volumes({master, music, sfx}); faders 0..1, squared
audio.set_paused(paused)                # muffles the music, quietens the ambience
audio.stats() -> Dictionary             # diagnostics
```

Buses (made in code): `Master` (the web desk's compressor and limiter with the makeup gain Web Audio adds, then a hard limiter), `Music` (low pass for menus and switches, a reverb for the switch swell), `Ambience` (`AmbLeft`, `AmbCentre`, `AmbRight` pan the events), `Sfx` (`SfxPage`, `SfxStage`, `UI`).

## Checking

```sh
$GODOT --headless --path . --script res://src/audio/dev/check.gd       # files, references, stem sync, the engine
$GODOT --path . res://src/audio/dev/audio_test.tscn                    # every song through switches, every effect, logged
$GODOT --path . res://src/audio/dev/audio_test.tscn --write-movie /tmp/tour.avi --fixed-fps 60 --resolution 160x90 --disable-vsync
ffmpeg -i /tmp/tour.avi -vn -acodec pcm_f32le /tmp/tour.wav
uv run --no-project --with soundfile --with numpy --with scipy python tools/audio/analyze_capture.py /tmp/tour.wav \
  "$HOME/Library/Application Support/Godot/app_userdata/Perspective Opus/audio_test.json"
```

`audio_test.tscn -- --steady=overture,finale` plays each song from its start in the conditions of the web build's `scripts/audio-render.ts --levels` (score and stage, all notes and none) so the loudness can be compared.
