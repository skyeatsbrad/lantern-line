# The Lantern Line

A fortress-train survival strategy game through a world without sunlight, built with Godot 4.7.2 and the Compatibility renderer.

**[Play The Lantern Line](https://skyeatsbrad.github.io/lantern-line/)**

![The Lantern Line gameplay](assets/screenshots/gameplay.png)

## v0.7 - September 22, 2026

The v0.7 release turns the presentation remaster into a clearer cross-device
gameplay experience:

- Corrected the documented route controls so **Up / Right / Down** commit the
  upper, middle, and lower rails, with direct `InputMap` regression coverage.
- Added physical-window-aware interface scaling, compact layout triggers, and
  bounded title/HUD geometry for short browser windows such as **844 x 390**.
- Replaced the four-page first-run instruction gate with a one-page quick
  start, then teaches pace and power priorities during play. The complete
  Conductor's Guide remains available at any time.
- Added rear-car-specific detachment guidance only when that decision becomes
  relevant.
- Rebalanced continuous repair so it requires a usable powered Workshop and
  no longer erases sustained damage without deliberate Repair investment.
- Increased the explicit scrap and special-resource premiums on dangerous
  routes, while preserving a real survival cost for reckless routing.
- Moved High Contrast enemy labels into a final foreground pass, separates
  colliding labels into readable rows, and adds leader lines when labels move.
- Expanded deterministic validation with physical-window scaling, quick-start,
  Workshop dependency, danger premiums, no-refit pressure, reckless routing,
  and coordinator-level Longshadow Focus checks.

## v0.6 - September 22, 2026

The v0.6 release completes a ground-up audiovisual and interface remaster while
preserving the deterministic strategy game:

- Rebuilt the world, train, threats, effects, and Longshadow around the original
  **Coal-lit Ink & Brass** visual language.
- Added an original six-state, 72 BPM score, procedural train ambience, victory
  and defeat stingers, and 70 deterministic sound effects.
- Added independent Master, Music, Ambience, SFX, and UI volume controls with
  browser-safe audio activation.
- Added distinct enemy silhouettes, readable attack telegraphs, Shadow Ward
  presentation, and phase-specific Longshadow visuals.
- Added responsive train and world framing for five-car consists at desktop and
  compact sizes without placing combat silhouettes behind the HUD.
- Rebuilt route, station, HUD, boss-card, scene-transition, and ending flows
  around clear hierarchy, keyboard focus, and bounded animation timing.
- Rebuilt the Dawn and Last Light Ledgers as responsive metric cards and
  structured journey reports with a fixed Return to Title action.
- Preserved High Contrast, 100%/115%/130% text, Reduced Motion, Reduced
  Flashes, independent screen shake, and non-audio equivalents for every
  critical cue.

## v0.5 - September 21, 2026

The v0.5 release locks the core mechanics and focuses on onboarding, presentation, and accessibility:

- Learn the game through a four-page, keyboard-friendly **Conductor's Guide** before the first run.
- Reopen the guide at any time with **H**, including from route and station screens.
- Open persistent **Accessibility & Presentation** options with **Escape** or the HUD button.
- Scale interface text to 100%, 115%, or 130%; large text automatically uses roomier responsive layouts.
- Enable a high-contrast theme with brighter borders, stronger focus rings, and on-screen enemy role/lens labels.
- Independently disable screen shake, reduce ambient motion, and reduce full-screen flash intensity.
- Shorten the hold-to-detach confirmation from 0.85 to 0.45 seconds.
- Navigate major overlays with Tab, Enter, Escape, and visible keyboard focus.
- Read notifications and critical warnings inside opaque, bordered panels rather than floating text.
- Scroll large-text options and ending ledgers without losing fixed close controls.

The complete v0.4 gameplay foundation remains intact:

- Aim the locomotive headlight into world-space rail junctions to choose routes.
- Discover 24 deterministic events, including three gated two-part story trails.
- Cycle between 1x, 1.5x, and 2x travel; combat scaling is capped and dense fields engage a visible **Threat Brake**.
- Use a wider stabilized scan beam at faster travel speeds without changing Focus precision.
- Manage clamped power priorities from 0-3 with visible full-load demand and priority-based brownout shedding.
- Track every car's integrity and powered state from a persistent consist readout.
- Spend lumen on **Focus Beam**, a narrow long-range burst with 4x light damage.
- Fire visible manual and automated Defense tracers from powered weapon platforms.
- Break late-run **Shadow Wards** with Focus or a Defense Salvo.
- Spend late-run scrap on field patches, twelve-second Overcharges, and wide **Signal Flares**.
- Reroll post-station route forecasts by spending scrap.
- Build within four starting coupling slots, then buy one permanent expansion to five.
- Preview power, speed, reserve endurance, and brownout consequences before station purchases.
- Use separate Build, Crew, and Refits station tabs that preserve selection and scroll position through transactions.
- Undo station transactions until departure, with a confirmation step for negative-power builds.
- Reorder the consist and assign four named crew members to compatible car posts.
- Hold to detach the rear car, with visible crew-loss or Safe Quarters evacuation consequences.
- Fight differentiated rear, roof, aerial, and warded threats with lens vulnerabilities and critical-car warnings.
- Defeat **The Longshadow** by completing one protected active response in each Veil, Tether, and Charge phase.
- Resume from versioned checkpoints, including exact boss phase state and deterministic wave cadence.
- Review cars, upgrades, field actions, wards, boss responses, power history, detachments, and crew in the Dawn Ledger.

## How to play

Open `project.godot` in Godot 4.7.2 or run an exported build.

| Input | Action |
|---|---|
| Mouse | Aim the headlight. During a route reveal, cursor height selects the upper, middle, or lower rail. |
| **1 / 2 / 3** | Select Standard / Hearth / Pale lens. |
| **F** | Fire Focus Beam when ready. |
| **C** | Fire the active Defense Salvo when a powered Defense Platform has a target. |
| **V / B / G** | Spend scrap on a field patch / emergency overcharge / signal flare. |
| **Q / W / E / R** | Raise Engine / Light / Defense / Repair priority. Hold Shift to lower it. Values stop at 0 and 3. |
| HUD priority buttons | Set an exact priority level from 0-3. |
| **Space** | Pause or resume. |
| **T** | Cycle 1x / 1.5x / 2x speed. |
| **H** | Open or close the Conductor's Guide. |
| **Escape** | Open or close Accessibility & Presentation options. |
| **Hold X** | Detach the rear car after the confirmation meter fills. |
| **Up / Right / Down** | Immediately commit the upper / middle / lower route. |

All major controls also have clickable UI equivalents.

## Run structure

1. **Travel:** Balance power, supplies, lumen, repairs, movement, and defense while aiming the headlight at approaching threats.
2. **Route reveals:** Every roughly 52 simulated seconds, inspect three forecast rail branches and commit one. After Waypost Five, spend scrap to reroll the offer.
3. **Waypost Five:** At 7,600 m, use the Build, Crew, and Refits tabs to preview and undo decisions before committing.
4. **The Longshadow:** At 14,500 m, match the displayed lens and complete an active Focus or Salvo response in every phase.
5. **Dawn Beacon:** After the boss falls, complete the final 300 m and review the Dawn Ledger.

A typical run lasts roughly 12-14 simulated minutes. 1.5x is the recommended live pace; 2x accelerates travel while threat pressure can automatically slow combat. Defeat occurs when locomotive integrity reaches zero or the crew remains without supplies long enough for the train to fail.

## Strategic systems

### Cars and upgrades

| Car | Role | Upgrade branches |
|---|---|---|
| Battery | Power generation | Deep Cells / Arc Reserve |
| Workshop | Repair and salvage | Field Foundry / Salvage Rig |
| Passenger | Supply efficiency and crew safety | Ration Lockers / Safe Quarters |
| Greenhouse | Passive resources | Hydroponics / Glowbeds |
| Defense | One weapon mount per car | Heavy Cannon / Flak Array |
| Utility | Rear protection and detachment | Plated Bulkhead / Breakaway Coupling |

Each car can receive only one upgrade. Purchases, repairs, ordering, slot expansion, and assignments are validated transactions, so failed actions do not consume resources.

When reserves fall into brownout, loads are shed by their selected priorities instead of every powered system failing simultaneously. The HUD and train both identify active, throttled, standby, offline, and destroyed cars.

### Crew

Crew bonuses apply only while that person is fit, assigned to a compatible surviving car, and occupying an available post. Combat destruction evacuates crew. A deliberate detachment loses occupants unless the detached Passenger car has Safe Quarters.

### Combat pacing and responses

Regular enemy pressure is capped at a readable field size. At accelerated travel speeds, a dense field, a newly introduced Shadow Ward, or critical train damage temporarily slows the simulation to 0.7x so the player can respond. The selected speed remains visible beside the effective automatic pace.

Longshadow phases protect one Focus and Salvo opportunity while locked. Focus is held instead of consumed when the wrong lens is selected, the target is not centered, or a transition is still forming. A failed Charge restores another response opportunity, but its locomotive and resource damage still lands.

### Accessibility and presentation

Settings save immediately and remain available from both the title and active run. Every resource, route category, danger forecast, power state, critical condition, and ability cooldown has a text cue rather than relying on color alone. High Contrast adds enemy labels such as `REAR / HEARTH [2]`, while the standard silhouettes remain distinct.

Reduced Motion freezes decorative parallax, smoke, sparks, boss bobbing, and detached-car drift. Reduced Flashes preserves hit markers and warning text while limiting full-screen overlays. Both options can be combined with disabled screen shake.

### Saves

Save schema v2 separates strategic run state from coordinator and encounter state. It preserves:

- Stable car IDs, order, integrity, upgrades, and slot capacity
- Crew status and car assignments
- Resources, priorities, lens and Focus timers
- Route history, seen-event pool, flags, and run history
- Reveal cadence and deterministic wave index
- Exact Longshadow phase, health, attack timers, target band, and Charge progress

Version 1 saves are migrated automatically. Invalid pending-run data is discarded without losing settings or meta progression.

## Architecture

```text
data/
  cars.json
  crew.json
  enemies.json
  lenses.json
  route_events.json
scripts/
  autoload/
    game_manager.gd
    audio_manager.gd
  combat/
    enemy.gd
    enemy_director.gd
    longshadow_encounter.gd
  run/
    game_world.gd
    run_snapshot.gd
    run_state.gd
    runtime_probe.gd
    smoke_test.gd
    train_stats.gd
  train/
    train_controller.gd
    train_renderer.gd
  ui/
    end_screen.gd
    hud.gd
    route_choice.gd
    station_panel.gd
  world/
    light_profile.gd
    route_director.gd
    route_projection.gd
    world_renderer.gd
```

`game_world.gd` is the only cross-system coordinator. `RunState` owns serializable strategic state, `TrainStats` is the shared derived-stat snapshot, and `LightProfile` is the single source of truth for rendered and simulated beam geometry.

## Validation

Run from PowerShell:

```powershell
& "C:\Users\bradleywo\Tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import

$env:LANTERN_SMOKE = "1"
& "C:\Users\bradleywo\Tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path .

$env:LANTERN_PROBE = "1"
& "C:\Users\bradleywo\Tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path .
```

The deterministic suite covers settings normalization, accessibility panels,
physical-window scaling, route-key mappings, quick-start and full-guide flows,
large-text theming, reduced flashes, short hold actions, save migration,
malformed-save rejection, priority clamping, brownout recovery, Workshop-bound
repairs, station previews, tab persistence and undo, field actions, route
premiums, route uniqueness and chain effects, threat-pressure limits, Shadow
Wards, crew loss and evacuation, Focus geometry, manual salvos, protected boss
responses through the real coordinator, no-refit and reckless campaigns, three
complete strategy archetypes, and a six-seed balance sweep. The reference
campaigns finish in approximately 12-14 simulated minutes.

Godot may print `ObjectDB` or `CanvasItem` cleanup warnings while the headless test process exits; these are engine teardown warnings and do not change a successful exit code.

## Export

```powershell
& "C:\Users\bradleywo\Tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Web"
& "C:\Users\bradleywo\Tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop"
```

- Web output: `build\web\`
- Windows output: `build\windows\TheLanternLine.exe`
- GitHub Pages source: `docs\`

## Credits

Original concept, design, writing, art direction, and implementation: **The Lantern Line**.
