# Step 7 UI and Cinematic-Flow Audit

Date: September 22, 2026

Verdict: **Approved with non-blocking Step 8 deferrals.**

## Scope

This audit covers responsive world framing, the gameplay HUD, route and station
modals, warning priority, Longshadow phase cards, scene transitions, ending
flow, keyboard focus, and the Dawn and Last Light Ledgers.

The review included:

- `scripts/ui/ui_theme.gd`
- `scripts/ui/hud.gd`
- `scripts/ui/route_choice.gd`
- `scripts/ui/station_panel.gd`
- `scripts/ui/end_screen.gd`
- `scripts/main.gd`
- `scripts/run/game_world.gd`
- `scripts/run/runtime_probe.gd`
- `scripts/run/smoke_test.gd`
- `scripts/train/train_renderer.gd`
- `scripts/world/world_renderer.gd`
- `scripts/world/route_projection.gd`
- `scripts/combat/enemy_director.gd`
- `scripts/combat/longshadow_encounter.gd`
- `scripts/presentation/presentation_director.gd`
- Desktop and compact accessibility capture matrices
- Web and Windows release packages

## Independent finding and correction

### Route and station exits were shorter than their authored timing band

The independent review found that route and station panels shared the generic
0.18-second panel exit. This met the 0.18-0.32-second generic panel target but
fell below the separate 0.25-0.5-second route and station target.

**Correction:** `UITheme.animate_panel_out()` now accepts a full-motion duration,
and route and station exits use `UITheme.MODAL_EXIT_SECONDS`, set to 0.26
seconds. Reduced Motion keeps the existing short 0.1-second fade with no
spatial movement.

The smoke suite now verifies that:

- The configured modal duration remains inside 0.25-0.5 seconds.
- Full-motion route and station exits do not finish before 0.25 seconds.
- Both exits finish before 0.5 seconds.
- Duplicate route and station inputs remain rejected during closure.

No other blocking or important defect was found.

## Responsive framing review

- The complete five-car consist remains inside the viewport at 1280 x 720 and
  compact 960 x 540.
- Train wheels, rails, route projections, enemies, and Longshadow geometry
  remain above the bottom HUD safe area.
- Pursuer targets reserve enough lower clearance for the complete leg
  silhouette and line width.
- Headlight, salvo, impact, enemy, and boss origins follow the scaled train
  geometry.
- Compact 130% text uses a two-line consist summary that exposes all five cars.
- The gameplay HUD remains visible in the critical-train showcase instead of
  reserving an unexplained empty strip.

## Interaction and cinematic review

- Route and station modals block interaction with controls beneath them.
- Route commitment, station tabs, and the ending return action receive keyboard
  focus.
- The ending return action stays outside the scrolling report and remains
  visible in the initial viewport.
- Normal notifications yield to cinematic phase cards, while critical warnings
  override both.
- Critical information retains explicit text and shape cues rather than relying
  only on color, sound, motion, or flashing.
- Longshadow entrance and phase gates remain exactly 3.0 and 2.5 seconds.
- Longshadow mechanic labels are suppressed during protected phase cards.
- Defeat reveal remains 1.6 seconds.
- Title/run fades remain 0.28 seconds, or 0.12 seconds with Reduced Motion.
- Anchored cinematic controls use fade-only entry where position tweening could
  conflict with layout.
- Reduced Motion removes nonessential spatial travel while retaining short
  state-confirming fades.

## Ending ledger review

- Dawn and Last Light use the same responsive report structure.
- Journey, Power and Combat, Consist, and Crew sections remain readable at
  desktop 100% and compact 130% text.
- Key outcome metrics use bounded cards rather than a single dense paragraph.
- The fixed Return to Title action remains visible and keyboard-focused without
  requiring the report to be scrolled.
- Rebuilding an ending report does not replay its audio.

## Capture review

The final review used:

- 11 default captures at 1280 x 720.
- 12 accessibility captures at 960 x 540 with 130% text, High Contrast,
  Reduced Motion, Reduced Flashes, and screen shake disabled.
- Reference scenes covering title, travel, dense combat, route reveal, station,
  critical train damage, all three Longshadow phases, Dawn Ledger, and the boss
  phase banner.
- An additional compact maximum-consist capture.

The matrices are stored outside the repository at:

- `files/step7-default`
- `files/step7-accessible`

The route modal, station panel, boss banner, critical-train HUD, maximum
consist, and ending action remained bounded and legible in the reviewed
captures.

## Regression and performance validation

- Godot 4.7.2 import and script compilation: passed.
- Full deterministic smoke suite: passed after the audit correction.
- Packaged Windows smoke suite: passed.
- Reference campaign: victory at 742.0 simulated seconds with 12 route
  commitments.
- Beam, Gunline, and Sustain strategy archetypes: passed.
- Adaptive seeds 101, 202, 303, 404, 505, and 606: passed.
- Desktop live gameplay: 60 FPS, approximately 17.01 ms average frame time.
- Compact accessibility live gameplay: 60 FPS, approximately 17.01 ms average
  frame time.
- Desktop dense combat: 60 FPS, approximately 17.04 ms average frame time.
- Compact accessibility dense combat: 60 FPS, approximately 17.07 ms average
  frame time.
- `git diff --check`: passed with line-ending conversion warnings only.

## Final Step 7 packages

- Web export: passed.
- Windows export: passed.
- Web PCK: 3,806,328 bytes.
- Windows PCK: 3,806,328 bytes.
- Matching package SHA-256:
  `146ECC951C45087C91A10262320E47D0D19787A6572BC95041274DBBC97F4CAE`.
- PCK growth from approved Step 6: 30,160 bytes.
- Both packages include the Atkinson Hyperlegible and Bitter OFL files.
- Both packages exclude `design/`.
- Both packages exclude standalone mechanical-tick assets.
- The 5,334,291-byte source audio library remains below its 8 MB target.
- The final PCK remains below the 12 MB remaster budget.

## Non-blocking Step 8 deferrals

- Promote visible title and Windows metadata from v0.5 to v0.6.
- Perform the final browser playtest and confirm the published GitHub Pages PCK
  matches the local release hash.
- Recheck the intentional instant hide of the world-space route projection
  beside the animated route modal during the final browser polish pass.
- Keep the station market and refit grids in the final compact-browser capture
  set so future column changes cannot regress independently.

## Approval

Step 7 meets the authored responsive-layout, keyboard, accessibility, timing,
warning-hierarchy, cinematic-flow, performance, Web, and package constraints.
Step 8 release validation and publication may begin.
