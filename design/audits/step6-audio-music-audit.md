# Step 6 Audio and Music Audit

Date: September 22, 2026

Verdict: **Approved with non-blocking Step 8 deferrals.**

## Scope

This audit covers the complete original score, procedural train soundscape,
semantic cue library, runtime mixing, browser gesture gate, accessibility
equivalence, deterministic generation, performance, and release-package cost.

The review included:

- `tools/generate_audio_assets.py`
- `tools/requirements-audio.txt`
- `assets/generated/audio/manifest.json`
- `scripts/autoload/audio_manager.gd`
- `scripts/presentation/presentation_director.gd`
- `scripts/run/game_world.gd`
- `scripts/combat/enemy_director.gd`
- `scripts/ui/station_panel.gd`
- `scripts/run/runtime_probe.gd`
- `scripts/run/smoke_test.gd`
- `scripts/ui/settings_panel.gd`
- `scripts/autoload/game_manager.gd`
- `default_bus_layout.tres`
- Web and Windows release packages

## Independent findings and corrections

### 1. Unused standalone mechanical ticks

The first audit found that `mechanical_tick_01.wav` through
`mechanical_tick_03.wav` were generated but never played directly. Their
generator remains useful as an internal texture for repair and route-commit
cues.

**Correction:** Removed the standalone group and files while retaining
`make_mechanical_tick()` for cue composition. The manifest and both release
packages contain no standalone mechanical-tick assets. Smoke coverage now
asserts that the group does not return.

### 2. Crossfade duration was not pinned

The runtime exercised crossfades but did not directly protect the authored
1.8-second duration.

**Correction:** The smoke suite now asserts
`AudioManager.MUSIC_CROSSFADE_SECONDS == 1.8`.

### 3. Short stinger stream was implicit

The dedicated victory/defeat stinger can briefly overlap the two score players.
This did not violate the intent of the two-long-stream limit, but the contract
did not say so explicitly.

**Correction:** The presentation bible now identifies the stinger as a short
dedicated stream outside the two long-loop slots while retaining the global
16-voice ceiling.

### 4. Threat-announcement panning was not documented

Threat and ward announcements use a fixed rightward pan rather than a live
entity position.

**Correction:** The presentation bible now records that this is intentional:
all announced threats enter through the shared right-side spawn corridor.
Combat impacts and defenses continue to use their event positions.

### 5. Cached Ogg loop metadata was fragile

Setting loop metadata directly on a ResourceLoader-cached stream could affect a
future non-looping use of the same path.

**Correction:** Looping Ogg resources are duplicated before their loop metadata
is changed.

## Final production library

- 6 original 72 BPM, 16-bar stereo score loops.
- 2 original stereo ending stingers.
- 70 mono sound-effect files.
- 78 media files across 24 semantic groups.
- 5,334,291 source bytes.
- Deterministic manifest SHA-256:
  `71EE74BF014997A03D82FCC8DB9E89F1CF65733621FEB80C1CC1996D7AAD2490`.
- Two consecutive generations reproduced every media file and the manifest
  byte-for-byte.
- Manifest provenance states that the library uses no external samples or
  recordings.

## Signal-quality review

Every generated file was decoded and checked after the final regeneration.

- Peak range: -12.29 to -0.89 dBFS.
- RMS range: -23.27 to -10.01 dBFS.
- Maximum DC offset: 0.002957.
- Maximum music loop-boundary discontinuity: 0.003237 full scale.
- All six score loops decode to 53.333 seconds at 22,050 Hz stereo.
- Every score loop contains stereo side information.
- No file is silent, non-finite, clipped, missing, or inconsistent with its
  manifest metadata.
- All repeated semantic cue families contain three deterministic variants.

The generator measures the written, decoded files rather than the pre-encode
source arrays, so Ogg metadata reflects actual shipped audio.

## Runtime and accessibility review

- Audio remains silent until an intentional keyboard or pointer gesture.
- Six score states resolve through two music players with a 1.8-second
  crossfade.
- Music tempo does not follow simulation speed.
- Defeat fades to silence and plays the defeat stinger.
- Victory selects the dawn state and plays the victory stinger.
- Procedural ambience covers engine, boiler, wheel, rail, wind, carriage, and
  Longshadow pressure layers.
- Station ambience removes most wheel percussion and widens the field.
- Repeated cues rotate deterministically.
- Positional SFX feed left, center, or right child buses into the user-facing
  SFX bus.
- Master, Music, Ambience, SFX, and UI volumes remain independent and
  persistent.
- Every critical audible warning retains visible or textual information.
- Presentation audio does not alter strategic timers, boss gates, or
  `Engine.time_scale`.

Repeated audio-probe runs observed 12-13 simultaneous voices and no more than
two simultaneous music players. The structural ceiling remains 16 voices.
The final recorded run completed at approximately 121 FPS and 9.05 ms average
frame time in the headless audio-probe environment.

Godot may print known ObjectDB/resource teardown warnings after a successful
headless audio probe. The probe exits successfully after stopping players and
clearing runtime caches; the warnings do not occur during normal gameplay.

## Regression and package validation

- Full deterministic smoke suite: passed.
- Three strategy archetypes: passed.
- Adaptive seeds 101, 202, 303, 404, 505, and 606: passed.
- Audio gesture, crossfade, state, variant, panner, and voice checks: passed.
- Web export: passed.
- Windows export: passed.
- Web PCK: 3,776,168 bytes.
- Windows PCK: 3,776,168 bytes.
- Matching package SHA-256:
  `60C29CA388B6C067ECDECA4F271942DA084266A044C63E3918CF2EEF91C6AC32`.
- PCK growth from approved Step 5: 3,024,832 bytes.
- Both PCKs include both bundled font-license files.
- Both PCKs exclude `design/`.
- Both PCKs exclude the removed standalone mechanical ticks.
- `git diff --check`: passed with line-ending conversion warnings only.

The audio source library remains below the 8 MB target, and the final PCK
remains below the 12 MB remaster budget.

## Non-blocking release deferrals

- The 12-player one-shot pool uses bounded FIFO reuse. An event burst above the
  pool limit can truncate the oldest one-shot without a fade; this should be
  listened for during the Step 8 browser playtest.
- Generated-only boss and threat cues intentionally have no synthesized
  fallback. Import and smoke checks fail if those production resources are
  missing.
- Byte-for-byte generation is proven on the pinned Windows toolchain; a
  cross-platform CI matrix is not required for this release.
- If Godot is upgraded, confirm that duplicated `AudioStreamOggVorbis`
  resources preserve independent loop metadata.

## Approval

The final system meets the authored identity, originality, accessibility,
runtime, determinism, voice, Web, and package constraints. Step 7 may begin.
