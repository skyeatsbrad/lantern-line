# Step 5 audit: combat, effects, and Longshadow remaster

Date: 2026-09-22

## Scope

Step 5 extends the Coal-lit Ink & Brass presentation language across regular
combat and the Longshadow finale:

- Shape-first Pursuer, Boarder, and Drainer silhouettes.
- Broken-orbit Shadow Wards and layered attack telegraphs.
- Deterministic, bounded spark, ward, shadow, tracer, flash, shake, and
  detachment effects.
- Distinct Veil, Tether, and Charge bodies, mechanics, response locks, and
  countdown treatment.
- Disposable combat and boss showcase profiles plus a sustained dense-combat
  benchmark.
- Reduced Motion, Reduced Flashes, High Contrast, screen-shake, and 130% text
  adaptations.

The audit combined direct code review, six deterministic capture profiles, the
full deterministic smoke suite, uncapped runtime benchmarks, fresh Web and
Windows exports, and two independent read-only reviews.

## Findings and corrections

### 1. Warded combat labels competed for the same space

**Severity:** Medium

The first combat pass could place the High Contrast role label, ward
instruction, and attack warning in overlapping vertical bands.

**Correction:** Warded role labels move above the ward, attack warning text
moves below it, and warded attack arcs use a distinct outer radius band. The
inner broken orbit, outer danger arcs, role text, ward instruction, health bar,
and target line remain separable in both default and compact High Contrast
captures.

### 2. Longshadow response instructions were hidden behind the HUD

**Severity:** Medium

The world-space lens and active-response instruction was initially drawn below
the boss, where the bottom HUD obscured it at desktop and compact resolutions.

**Correction:** The response instruction is now centered above the boss title
and health bar. Its width supports the longest instruction at 130% text scale.
The Charge countdown occupies a separate line above the response instruction,
so it no longer collides with the boss health bar.

### 3. Protected boss timing needed explicit regression locks

**Severity:** Medium

The implementation preserved the required entrance and transition gates, but
the smoke suite did not directly pin their design values.

**Correction:** `LongshadowEncounter.ENTRANCE_DURATION` is explicitly locked
to 3.0 seconds and `TRANSITION_DURATION` to 2.5 seconds. Smoke coverage verifies
both literal contract values and the timers applied at encounter start and the
Veil-to-Tether transition. The 1.1-second presentation flourish remains inside
those protected gates and does not affect strategic time.

### 4. Dense benchmark assumptions could interrupt validation

**Severity:** Medium

The first sustained-combat probe assumed a three-car starting consist and could
cross the station threshold, allowing the station modal to interrupt detach
verification.

**Correction:** The probe records the prepared consist's expected post-detach
count and marks the benchmark station as completed. Dense combat now reaches
its intended end state without changing real campaign behavior.

### 5. Ground-threat leg tips can pass behind the bottom HUD

**Severity:** Low, deferred

The lowest portions of ground Pursuer silhouettes can sit behind the bottom HUD
at both default and compact resolutions. The role label, health bar, attack
warning, target line, and all controls remain visible, so no combat information
or interaction is lost.

Both independent reviews ruled this non-blocking for Step 5. Responsive
world/HUD framing is recorded for Step 7 alongside the existing maximum-consist
framing work rather than changing combat geometry in this pass.

## Visual matrix

The final captures were generated from disposable state and inspected:

- `design/captures/step5-combat.png`
- `design/captures/step5-combat-compact-accessible.png`
- `design/captures/step5-boss-veil.png`
- `design/captures/step5-boss-tether.png`
- `design/captures/step5-boss-charge.png`
- `design/captures/step5-boss-charge-compact-accessible.png`

Together they cover all three regular threat roles, warded and attacking
states, target connections, all three Longshadow phases, desktop presentation,
and the combined 960x540 accessibility profile.

## Performance verification

Final uncapped runtime probes reported:

- Standard 1280x720 desktop: 314 FPS, 3.05 ms sampled average frame time,
  353 draw calls.
- Sustained dense 1280x720 combat: 233 FPS, 4.39 ms sampled average frame
  time, 450 draw calls.
- 960x540 combined accessibility profile: 424 FPS, 2.20 ms sampled average
  frame time, 281 draw calls.

The combat and boss pass remains substantially above the locked 60 FPS desktop
and 30 FPS compact requirements.

## Regression and package verification

- Full deterministic smoke suite: passed.
- Three campaign archetypes: passed.
- Adaptive seeds 101, 202, 303, 404, 505, and 606: passed.
- Protected 3.0-second entrance gate: passed.
- Protected 2.5-second phase transition gate: passed.
- Combat and boss capture matrix: passed.
- Web export: passed.
- Windows export: passed.
- Web PCK: 751,336 bytes.
- Windows PCK: 751,336 bytes.
- Matching SHA-256:
  `4C1C7F80DA696D08DF56827F951983F673E5C2CD9325E36DBA0A05EF8CFDB557`.
- Both PCKs contain the Atkinson Hyperlegible and Bitter OFL files.
- Both PCKs contain no `design/` paths.
- `git diff --check`: passed with line-ending conversion warnings only.

## Verdict

**Approved with one non-blocking Step 7 framing deferral.** Regular threats,
wards, telegraphs, combat effects, and all Longshadow phases now have distinct,
accessible presentation without changing deterministic combat outcomes or
protected boss timing. Step 6 may begin.
