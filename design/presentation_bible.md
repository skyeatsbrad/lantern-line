# The Lantern Line v0.6 Presentation Bible

## Release identity

**The Lantern Line v0.6 - Coal-lit Ink & Brass**

This remaster changes presentation only. Gameplay rules, deterministic simulation,
save behavior, resource economy, encounter timing, and campaign outcomes remain
unchanged unless a later audited step identifies a presentation-coupled defect.

## Baseline

Captured from v0.5 commit `98f6e4d56b8335ad11835dbc05dcfa045588ebda`.

| Measure | v0.5 baseline |
|---|---:|
| Web package (`index.pck`) | 362,080 bytes |
| Windows executable | 109,144,576 bytes |
| Repository files | 148 |
| Source/config/data bytes | 351,336 |
| Image bytes | 260,560 |
| Imported audio files | 0 |
| Canvas shaders | 0 |
| Frame-time/draw-call instrumentation | Not present in v0.5 |
| Reference viewport | 1280 x 720 |
| Compact viewport | 960 x 540 |

Current visuals are immediate-mode drawings owned by:

- `scripts/world/world_renderer.gd`
- `scripts/train/train_renderer.gd`
- `scripts/combat/enemy_director.gd`
- `scripts/combat/longshadow_encounter.gd`
- `scripts/effects/effects_layer.gd`

Current sound is generated at runtime by
`scripts/autoload/audio_manager.gd` at 22,050 Hz. It has one master volume,
six pooled players, a procedural engine bed, ten synthesized cues, no music,
no imported audio, and no positional sound.

## Concept target

See `design/concepts/coal-lit-ink-brass.svg`.

The scene must read first as a fortress train crossing an impossible night,
then reveal mechanical and supernatural detail on closer inspection.

### Visual hierarchy

1. The headlight and the locomotive are the brightest focal point.
2. Threat silhouettes remain readable before their internal detail.
3. Train-car type and condition remain readable at compact resolution.
4. Route, station, warning, and boss information remain above decoration.
5. Background motion and particles never compete with aiming.

## Palette

All presentation code must reference semantic palette entries instead of
introducing independent hardcoded colors.

| Token | Hex | Use |
|---|---|---|
| `night_void` | `#080B11` | Deep sky and negative space |
| `coal` | `#111721` | Main silhouette fill |
| `iron` | `#202A36` | Near terrain and inactive metal |
| `slate` | `#354455` | Lit steel and secondary detail |
| `bone` | `#E8DFC6` | Primary text and bright neutral detail |
| `brass` | `#D6A04F` | Train trim, selected controls, lantern hardware |
| `ember` | `#F2A24C` | Headlight, sparks, active mechanisms |
| `flame` | `#DF6438` | Damage, heat, urgent action |
| `cold_signal` | `#6CA6C6` | Pale lens, aerial threats, route machinery |
| `shadow_veil` | `#7C3C78` | Longshadow and corruption |
| `growth` | `#7EA36B` | Supplies, greenhouse, recovery |
| `danger` | `#F0553D` | Critical state and attack timing |
| `pursuer_rust` | `#A94C44` | Pursuer identity before attack warnings |
| `boarder_ochre` | `#B8893F` | Boarder identity before attack warnings |
| `drainer_glow` | `#5D95AA` | Drainer identity before Pale-lens emphasis |

High Contrast uses the same semantic roles with brighter values, heavier
outlines, opaque labels, and shape/text reinforcement.

## Shape language

### Train

- Heavy horizontal masses with 2-4 px brass edge accents.
- Every car family has a different roofline and window/glyph rhythm.
- Wheels, rods, turrets, greenhouse frames, and couplings use visible
  mechanical motion.
- Upgrades add silhouette-level attachments instead of recolors alone.
- Damage progresses through dents, soot, missing panels, sparks, and heat.

### Threats

- Pursuer: low, angular, six-point rail predator with a forward hot eye.
- Boarder: tall hooked figure with long climbing limbs and a crescent tool.
- Drainer: floating hollow core with four asymmetrical tendrils.
- Ward: broken orbit, not a generic circular shield.
- Longshadow: layered void body whose phase changes its negative-space shape.

These are explicit geometry replacements, not recolors of the current drawing
code. The combat remaster must replace the current symmetric Drainer, complete
ward circle, and phase-invariant Longshadow body while preserving their
simulation, hit geometry, and accessibility labels.

### Environment

- Four depth bands: sky, far ruins, mid terrain, near debris.
- Repeated route families are seeded from the run and event category.
- Visual landmarks include dead signal towers, bridge ribs, lantern colonies,
  flooded cuttings, bone forests, collapsed stations, and industrial shrines.
- Texture is etched and sooty rather than painterly or photorealistic.

## Lighting and effects

- Primary light is the headlight, represented by a feathered additive cone.
- One secondary locomotive/cabin glow is allowed.
- Combat flashes are local whenever possible; full-screen flashes remain rare.
- One inexpensive overlay may add vignette and static grain without reading
  the already-rendered screen.
- Gameplay-critical hit rings and tracers remain deterministic pooled effects.
- Continuous particles are limited to smoke, ash, fog, and sparks.
- No chromatic aberration, bloom chain, or shadow field is required for the
  target look.

## Motion grammar

| Motion | Timing | Character |
|---|---:|---|
| UI confirmation | 0.10-0.18 s | Immediate, small scale/brightness response |
| UI panel transition | 0.18-0.32 s | Fade plus short vertical travel |
| Train idle cycle | 0.7-1.4 s | Heavy, repeating mechanical rhythm |
| Threat anticipation | 0.35-0.8 s | Clear wind-up, held silhouette |
| Threat impact | 0.08-0.16 s | Sharp local impulse |
| Heavy train reaction | 0.25-0.55 s | Damped suspension and sparks |
| Route/station transition | 0.25-0.5 s | Signal sweep, no long camera travel |
| Boss phase flourish | 0.7-1.2 s | Visual motion inside the existing protected phase gate |

`AnimationPlayer` owns repeatable authored sequences. Tweens own values whose
destination is only known at runtime. Presentation must not change
`Engine.time_scale` or alter strategic simulation timing.

Longshadow's existing 2.5-second phase-transition gate and 3-second entrance
gate are simulation timing and remain unchanged. The shorter timing above
applies only to the visual flourish inside that protected interval.

Reduced Motion replaces parallax, position travel, rotation, shake, and drift
with opacity, color, outline, and static-state changes.

## Typography

- UI/body target: Atkinson Hyperlegible, regular and bold.
- Display target: Bitter SemiBold.
- Fonts must be bundled with their OFL license text.
- Gameplay values remain tabular-looking and aligned.
- Display typography never replaces plain-language control labels.
- Existing 100%, 115%, and 130% text settings remain authoritative.

## Audio identity

### Score

- 72 BPM industrial chamber pulse in D minor.
- Rail percussion, low harmonium/drone, bowed metal, restrained low strings,
  distant horn intervals, and a small recurring three-note lantern motif.
- Musical tempo remains stable when travel speed changes.
- Threat pressure selects pre-rendered intensity states, not playback pitch.
- Music is rendered as original stereo loops from oscillators, filtered noise,
  resonators, and envelopes. It uses no sampled instruments or recordings.
- Runtime uses two music players only: the active loop and the next loop during
  a crossfade. Travel ambience remains the procedural 22,050 Hz generator and
  therefore does not consume a long compressed-stream slot.
- Target music set: title, travel calm, travel tension, station, Longshadow,
  and dawn, plus short victory/defeat stingers. Loops target 45-60 seconds at a
  compressed size that keeps the complete audio addition below 8 MB.
- Victory and defeat use one dedicated short-stinger player. A stinger may
  briefly overlap a music crossfade, but it is not a long-stream slot and the
  complete mix must remain within the 16-voice ceiling.

### Soundscape

- Engine bed: piston, boiler, wheel, rail, wind, and carriage resonance layers.
- Threats have positional cues but retain visual/text equivalents. Announcement
  cues use a fixed rightward pan because the shared threat spawn corridor is to
  the right; combat impacts and defenses use their event positions.
- Each repeated impact or mechanical cue has at least three variants.
- Longshadow uses low-frequency pressure, reversed metallic textures, and
  phase-specific motifs without masking warning sounds.
- Station ambience removes most percussion and opens the stereo field.
- Dawn resolves the lantern motif into a warmer major voicing.

### Runtime mix

| Bus | Role |
|---|---|
| Master | Global level and final safety |
| Music | Score and stingers |
| Ambience | Engine, rail, wind, environmental loops |
| SFX | Combat, train damage, mechanisms, enemies |
| UI | Navigation, confirmation, rejection |

Core reverb and mastering are baked into generated files for Web parity.
Runtime bus effects are not required for the presentation to work.

All generated sound and music is original project output. No external samples,
impulse responses, recordings, or instrument packs are permitted unless a
later audit records the source, license, checksum, and required attribution in
an asset manifest.

## Production constraints

- Godot 4.7.2 Compatibility renderer remains mandatory.
- Web export remains single-threaded.
- Added PCK budget: 12 MB maximum.
- Default target: sustained 60 FPS at 1280 x 720 desktop Web.
- Compact floor: sustained 30 FPS at 960 x 540.
- Maximum continuous ambient particles: 250.
- Maximum active presentation lights: 2.
- Maximum simultaneous audio voices: 16.
- Maximum long compressed streams: 2, reserved for music crossfades.
- Maximum full-screen presentation overlay: 1.

Step 2 must add a runtime presentation performance monitor before introducing
new shaders, particles, or lights. It records average and worst frame time,
rendered objects, draw calls, audio voices, and package size in deterministic
reference scenes. Until that harness exists, the v0.5 frame-time baseline is
explicitly unknown rather than assumed.

## Accessibility invariants

- No critical state is communicated only by color, sound, animation, or flash.
- No effect flashes more than three times in one second.
- Reduced Flashes limits full-screen alpha and duration.
- Reduced Motion disables nonessential spatial motion.
- High Contrast preserves labels and strengthens outlines/focus indicators.
- New audio categories receive independent volume controls.
- Audio starts only after intentional user input.
- New controls support keyboard focus and clickable operation.

## Validation matrix

Every major presentation step must be checked in:

- 1280 x 720 and 960 x 540.
- Text scale 100% and 130%.
- Default and High Contrast.
- Default and Reduced Motion.
- Default and Reduced Flashes.
- Web and Windows exports.

Reference scenes:

1. Title.
2. Early travel.
3. Dense combat.
4. Route reveal.
5. Station.
6. Critical train damage.
7. Longshadow Veil.
8. Longshadow Tether.
9. Longshadow Charge.
10. Dawn Ledger.

## Step gates

Each production step must finish with:

1. Godot import/compile.
2. Targeted tests for the changed surface.
3. Full deterministic smoke suite when behavior-facing code changed.
4. Default and accessibility screenshots.
5. Performance-monitor comparison for any rendering or audio change.
6. Web package-size comparison.
7. A written audit that identifies defects before the next step begins.
