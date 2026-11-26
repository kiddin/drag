<p align="center"><img src="Resources/AppIcon.png" width="160" alt="Screech icon"></p>

# Screech

Drag a window and hear it drag.

Screech lives in the menu bar and listens to your windows. Drag one and it sounds like furniture sliding across a floor, a stone slab grinding over tiles or a glass bowl sliding on a countertop. The sound follows your hand: drag faster and it gets louder and brighter, hesitate and it stutters, stop and it goes quiet. Resize a window and it squeals or creaks like the material being stretched.

## Private by construction

- **No network.** Screech contains no networking code and never checks for updates.
- **No permissions.** No Accessibility, no Screen Recording, no Input Monitoring, no microphone. It only sees which mouse button is down and where windows are, both of which macOS shares with any app.
- **No telemetry.** The only thing it stores is its own preferences, in `~/Library/Preferences/dev.screech.Screech.plist`.
- **Nothing runs while you are not dragging.** The audio engine starts when you press the mouse and pauses 20 seconds later, so it uses no CPU when idle.

## Requirements

- macOS 15 or newer, on Apple Silicon or Intel (the app is a universal binary).
- To build: Swift 6 or newer (Xcode 16 or newer, or its Command Line Tools).

## Install

```bash
make install
```

This builds Screech, signs it locally, copies it to `/Applications` (or `~/Applications`) and launches it. Look for the waveform in the menu bar, then drag any window.

From a release zip, unzip and run `./install.sh`. Release builds are signed ad hoc, not notarized, so the script removes the download quarantine. Only do that with a zip you trust; building from source avoids the question.

## Materials

Each material is a sound theme. Dragging plays a real recording; resizing and the knocks when you grab or let go are synthesized.

| Material | Drag | Resize |
|---|---|---|
| Wood | Furniture dragged over a floor | Slow creak |
| Rubber | A box squeaking along on rubber feet | Balloon screech that rises as you stretch |
| Metal | A metal stool pushed across a floor | Groaning squeal that rings out |
| Glass | A glass bowl sliding on a countertop | Wet-finger squeak |
| Stone | A stone slab grinding over tiles | Rumbling grind |

## Controls

| Control | Default | What it does |
|---|---|---|
| Volume | 70% | Overall loudness |
| Ring | 100% | How much the material resonates on resize and knocks: left is dry, right rings |
| Reverb | 35% | A small room around the sound |
| Drag sounds / Resize sounds | On | Turn either kind off |
| Launch at login | Off | Start Screech when you log in |

**Try drag** and **Try resize** in the menu play a scripted, uneven gesture, so you can hear a material without moving a window.

## How it works

**Watching windows.** A global mouse monitor reports button presses (this needs no permission, unlike keyboard monitoring). On a press, Screech finds the window under the pointer in `CGWindowListCopyWindowInfo` and samples that one window's bounds 120 times a second until the button comes up. Window *bounds* are public; titles and contents, which would need Screen Recording, are never read.

**Reading the motion.** `MotionAnalyzer` turns frames into a gesture:

1. **Drag or resize.** If the size changed, it is a resize; if only the origin moved, a drag. The first motion decides, so a drag that crosses screens never flips to resize.
2. **Speed.** Measured between frames that actually changed, because the window server updates at 60 Hz even when sampled at 120 Hz. Speed falls to zero after 50 ms without movement (90 ms for resizes, which update more slowly).
3. **Bumps.** A sharp reversal of direction triggers a knock.
4. **Pan and weight.** The window's position across all screens pans the sound; bigger windows make knocks and squeals lower.

**Making the sound.** Everything runs on the audio thread with no locks and no allocation; the tracker talks to it through atomics.

- **Drag** plays the material's recording as overlapping 160 ms grains taken from random places, so it never audibly loops. The playback rate follows your speed, from 0.7x at a crawl to 1.45x on a fling, the way a real object sounds lower and duller when pushed slowly. A low-pass filter opens with speed too.
- **Resize** is a bowed-string friction model (the stick-slip that makes a wet finger squeal on glass): speed sets pitch and pressure, and growing bends the pitch up while shrinking bends it down.
- **Knocks** on grab, release and direction reversals are short contact pulses into a bank of up to 48 resonant modes laid out like a real plate of the material.
- **Room.** An 8-line feedback delay network reverb, a gentle compressor and a soft clipper.

The recordings are public domain (CC0) from freesound.org; [`Resources/Samples/CREDITS.md`](Resources/Samples/CREDITS.md) lists each one. `scripts/prepare_samples.py` keeps only the steady dragging parts of each, removes pauses and stray knocks, and evens out the loudness.

## Uninstall

```bash
make uninstall
```

This quits Screech, removes its login item and deletes the app. Your preferences stay; remove them with:

```bash
defaults delete dev.screech.Screech
```

## Development

```bash
make app        # dist/Screech.app
make run        # build and run it from the terminal
make test       # DSP, motion analysis and recording playback tests
make previews   # render previews/<material>-{drag,resize}.wav from a scripted gesture
make release    # tests, then dist/Screech-vX.Y.Z.zip
make icon       # redraw Resources/AppIcon.icns
```

```
Sources/ScreechDSP/      pure Swift, unit tested: motion analysis, synth, recording playback
Sources/Screech/         the menu bar app: window tracking, audio output, menu
Sources/screech-render/  renders WAV previews offline, and --analyze prints loudness per speed
Tests/ScreechDSPTests/   synthetic drags and resizes, silence, bounds, materials
Resources/Samples/       one drag recording per material
scripts/                 icon drawing and recording preparation
```
