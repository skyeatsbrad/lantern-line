# Step 4 audit: world and train remaster

Date: 2026-09-21

## Scope

Step 4 extends the Coal-lit Ink & Brass language across the full travel view:

- Route-history-driven living, machinery, danger, and neutral atmosphere.
- Category landmarks, black rain, and semantic route projection.
- Bundled route fonts, category shapes, labels, threat levels, and selected
  treatment that does not rely on color alone.
- Distinct silhouettes for all six car types.
- Distinct permanent-refit geometry for all twelve upgrades.
- Deterministic integrity wear, power badges, crew markers, and critical-state
  treatment.
- Disposable route and train showcase capture profiles.

The audit combined direct visual review, deterministic regression tests,
fresh Web and Windows exports, capture-failure reproduction, and two
independent read-only reviews.

## Findings and corrections

### 1. Capture verification could report success before a PNG existed

**Severity:** High

The initial showcase probe exited on a fixed timer while its screenshot
coroutine was still waiting for a rendered frame. A headless run could
therefore report a successful capture without writing a file. Title capture
could wait indefinitely for the same unavailable frame signal.

**Correction:** Runtime captures now wait for completion, verify the save
result and file existence, reject duplicate completion, and fail with exit 10
after a bounded timeout. Title capture has an independent six-second watchdog,
verifies file existence, restores temporary settings on every exit path, and
fails with exit 11 when no render frame becomes available. Capture environment
variables now enter the probe without requiring an additional command-line
flag.

Direct reproduction confirmed:

- Headless train capture: exit 10 and no file.
- Headless title capture: exit 11 and no file.
- Environment-only graphical train capture: exit 0 with a valid PNG.

### 2. Bundled font licenses were omitted from exports

**Severity:** High

The font binaries were packed automatically, but the plain-text OFL files were
not resources and did not enter all-resources exports.

**Correction:** Both export presets explicitly include
`assets/fonts/OFL-Atkinson.txt` and `assets/fonts/OFL-Bitter.txt`. Fresh Web and
Windows PCKs contain both license paths.

### 3. Accessibility treatment was inconsistent in custom drawing

**Severity:** Medium

The first route pass used fixed custom-draw font sizes, the accessible
power-state badge clipped `STBY`, critical text bypassed the high-contrast
palette, category landmarks did not react to High Contrast, and integrity
scratches disappeared into dark car bodies.

**Correction:** Route labels and threat text now honor the authoritative
100%, 115%, and 130% text settings. Badge geometry expands with text scale.
Critical text and category atmosphere resolve through semantic high-contrast
colors. Damage scratches use exposed-metal contrast while soot remains dark.

### 4. Route context needed deterministic coverage

**Severity:** Medium

The world renderer correctly observed route history, but the mapping lacked a
targeted regression test and one showcase used a threat value that differed
from source data.

**Correction:** Smoke coverage now verifies latest-event category, event ID,
danger level, and unknown-event neutral fallback. Black Rain uses its
data-defined threat level of 2 in both showcase state and renderer context.

### 5. Maximum consists extend beyond the world-space framing

**Severity:** Low, deferred

This is inherited from v0.5's fixed train anchor rather than introduced by the
remaster. A five-car consist can extend beyond the left edge, especially at
compact resolution.

The independent re-audit ruled this non-blocking for Step 4 because gameplay
status always lists every car in `HUD._consist_status()`, all car transactions
occur in `StationPanel`, and no world-space car-picking interaction exists.
The world train is therefore presentation-only. Responsive consist framing is
recorded for the later UI and cinematic-flow polish rather than changing
combat geometry during this pass.

## Visual matrix

The final captures were generated from disposable state and inspected:

- `design/captures/step4-train-upgrades-a.png`
- `design/captures/step4-train-upgrades-b.png`
- `design/captures/step4-train-compact-accessible.png`
- `design/captures/step4-route-showcase.png`
- `design/captures/step4-route-compact-accessible.png`

Together they cover all six car types, all twelve upgrades, multiple integrity
and power states, all three route categories, desktop and compact layouts, and
the combined accessibility profile.

## Performance verification

The uncapped 1280x720 runtime probe reported:

- 460 FPS.
- 3.97 ms process monitor value.
- 2.13 ms average sampled frame time.
- 324 draw calls.
- 1,561 rendered objects.
- 24,569 primitives.
- 135 nodes.
- 33 resources.

The world-and-train pass remains far above the locked 60 FPS desktop and
30 FPS compact requirements.

## Regression and package verification

- Full deterministic smoke suite: passed.
- Route-context regression coverage: passed.
- Graphical runtime probe: passed.
- Headless capture failure paths: passed.
- Environment-only graphical capture: passed.
- Web export: passed.
- Windows export: passed.
- Web PCK: 728,424 bytes.
- Windows PCK: 728,424 bytes.
- Growth from approved Step 3 Web PCK: 28,396 bytes.
- Growth from v0.5 Web PCK: 366,344 bytes.
- Both PCKs contain both bundled font licenses.
- Both PCKs contain no `design/` paths.
- `git diff --check`: passed.

## Verdict

**Approved.** The full world and train presentation now communicates route
identity, car function, permanent upgrades, power, crew, and damage without
changing deterministic outcomes. Capture evidence, accessibility behavior,
license compliance, performance, and both release packages have been
independently re-audited and approved. Step 5 may begin.
