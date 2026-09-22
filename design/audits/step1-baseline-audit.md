# Step 1 Audit - Baseline and Art Direction

Date: September 21, 2026

## Reviewed

- v0.5 repository and release artifact sizes.
- `design/presentation_bible.md`.
- `design/concepts/coal-lit-ink-brass.svg`.
- Current world, train, enemy, boss, effects, UI-theme, and audio code.
- Godot 4.7.2 Compatibility/Web constraints.

## Findings and resolutions

### Boss phase timing

**Finding:** The first bible draft described a 0.7-1.2 second boss transition,
while Longshadow's 2.5-second phase gate and 3-second entrance gate are part of
simulation timing.

**Resolution:** The simulation gates remain unchanged. The shorter timing now
describes only the visual flourish inside the existing protected interval.

### Shape replacement scope

**Finding:** The target ward, Drainer, and Longshadow silhouettes cannot be
achieved by recoloring their current symmetric drawing code.

**Resolution:** The bible now explicitly scopes them as geometry replacements
for the combat-remaster step while preserving simulation and hit behavior.

### Music layering and stream budget

**Finding:** Open-ended adaptive layering conflicted with the two-long-stream
limit and the 12 MB package budget.

**Resolution:** Music is locked to pre-rendered state loops with two-player
crossfades. Engine/rail ambience remains procedural. The complete generated
audio addition targets less than 8 MB.

### Missing performance baseline

**Finding:** v0.5 has no frame-time or draw-call instrumentation, so future FPS
targets could not be objectively compared.

**Resolution:** This absence is now recorded rather than guessed. Step 2 must
build the monitor before introducing visual cost, and every later gate includes
a performance comparison.

### Semantic enemy colors

**Finding:** The concept reused `danger` and `ember` signal colors as permanent
enemy identity colors.

**Resolution:** Added `pursuer_rust`, `boarder_ochre`, and `drainer_glow`.
`danger` remains reserved for attack timing and critical state.

### Audio licensing

**Finding:** Font licensing was explicit, but audio sourcing was not.

**Resolution:** Audio is locked to original deterministic synthesis with no
external recordings, samples, instruments, or impulse responses. Any exception
requires a manifest entry and a later audit.

## Verification

- Baseline release sizes and commit match the existing v0.5 release.
- Concept SVG renders at 1280 x 720 with the intended hierarchy.
- Palette, shape, motion, audio, accessibility, package, and performance
  constraints are explicit enough to drive deterministic implementation.
- No gameplay or source files changed during Step 1.
- `git diff --check` is clean.

## Verdict

**Approved after corrections.** Step 2 may begin.
