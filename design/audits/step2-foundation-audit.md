# Step 2 audit: presentation foundation

Date: 2026-09-21

## Scope

This audit covers the v0.6 presentation foundation:

- Semantic normal and high-contrast palette.
- Atkinson Hyperlegible interface fonts and Bitter display font.
- Master, Music, Ambience, SFX, and UI audio buses.
- Independent saved volume settings.
- Presentation state derivation and runtime performance instrumentation.
- Deterministic generated visual and audio foundation assets.
- Runtime-probe reporting and deterministic smoke coverage.

The audit was performed as a read-only review of the complete working-tree
change set after the first implementation gate.

## Findings and corrections

### 1. Bitter rendered at the variable font's Thin default

**Severity:** High

The title loaded `Bitter-Variable.ttf` directly. Its default variation did not
meet the SemiBold display treatment defined in the presentation bible.

**Correction:** `UITheme.display_font()` now returns a cached `FontVariation`
with the `wght` axis fixed at 600. The smoke suite verifies that resolved
variation coordinate.

### 2. UITheme retained independent literal colors

**Severity:** Medium

Disabled controls, progress-bar chrome, and checkbox interaction colors still
used local color literals after the semantic palette was introduced.

**Correction:** Every color in `ui_theme.gd` now resolves through
`PresentationPalette`.

### 3. UI rejection and critical alarms shared one event and bus

**Severity:** Medium

Failed player actions and simulation-critical warnings both used `alarm`.
The new category sliders therefore could not distinguish interface rejection
feedback from threats, boss warnings, and critical train states.

**Correction:** Failed input and transaction feedback now uses `ui_reject` on
the UI bus. `alarm` remains on SFX and now resolves to a separate generated
critical-alarm cue. Procedural fallbacks remain available for both events.

## Verification after corrections

- Full deterministic smoke suite: passed.
- Generated audio and visual manifests: reproduced byte-for-byte.
- Graphical runtime probe at 1280x720:
  - 60 FPS.
  - 17.22 ms reported process time.
  - 17.01 ms average sampled frame time.
  - 215 draw calls.
  - 1,315 rendered objects.
  - 19,517 primitives.
  - 135 nodes.
  - 31 resources.
  - 0 active audio voices during the ungated probe.
- Web export: passed.
- Web PCK:
  - v0.5 baseline: 362,080 bytes.
  - Step 2: 719,748 bytes.
  - Growth: 357,668 bytes.
  - Remaining presentation budget: more than 11.6 MB.
- `git diff --check`: passed.

The probe's worst-frame value includes startup and is retained for comparison
with later steps; sustained playback held 60 FPS.

## Residual risks

- `mechanical_tick.wav` is intentionally reserved for the world/train pass and
  is not yet referenced.
- Long-form music streams are intentionally absent until the dedicated audio
  production step.
- The title still identifies the public build as v0.5 until the release step.

## Verdict

**Approved.** The foundation is coherent, deterministic, Web-safe, accessible,
and within the locked package and runtime budgets. Step 3 may begin.

