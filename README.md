# The Lantern Line

A fortress-train survival strategy game through a world without sunlight, built with Godot 4.7.2 and the Compatibility renderer.

**[Play The Lantern Line](https://skyeatsbrad.github.io/lantern-line/)**

![The Lantern Line gameplay](assets/screenshots/gameplay.png)

## v0.3 - September 20, 2026

The v0.3 release focuses on readable consequences, recoverable power failures, active combat, and a finale with room to breathe:

- Aim the locomotive headlight into world-space rail junctions to choose routes.
- Discover 24 deterministic events, including three gated two-part story trails.
- Manage clamped power priorities from 0-3 with visible full-load demand and priority-based brownout shedding.
- Track every car's integrity and powered state from a persistent consist readout.
- Spend lumen on **Focus Beam**, a narrow long-range burst with 4x light damage.
- Fire a manual **Defense Salvo** from powered weapon platforms.
- Spend late-run scrap on field patches and emergency power/lumen overcharges.
- Build within four starting coupling slots, then buy one permanent expansion to five.
- Preview power, speed, reserve endurance, and brownout consequences before station purchases.
- Undo station transactions until departure, with a confirmation step for negative-power builds.
- Reorder the consist and assign four named crew members to compatible car posts.
- Hold to detach the rear car, with visible crew-loss or Safe Quarters evacuation consequences.
- Fight differentiated rear, roof, and aerial threats with clearer warnings.
- Defeat **The Longshadow** across paced Veil, Tether, and Charge phases with distinct tactical prompts.
- Resume from versioned checkpoints, including exact boss phase state and deterministic wave cadence.
- Review cars added, upgrades, field actions, power history, detachments, and crew in the Dawn Ledger.

## How to play

Open `project.godot` in Godot 4.7.2 or run an exported build.

| Input | Action |
|---|---|
| Mouse | Aim the headlight. During a route reveal, cursor height selects the upper, middle, or lower rail. |
| **1 / 2 / 3** | Select Standard / Hearth / Pale lens. |
| **F** | Fire Focus Beam when ready. |
| **C** | Fire the active Defense Salvo when a powered Defense Platform has a target. |
| **V / B** | Spend scrap on a field patch / emergency overcharge. |
| **Q / W / E / R** | Raise Engine / Light / Defense / Repair priority. Hold Shift to lower it. Values stop at 0 and 3. |
| HUD priority buttons | Set an exact priority level from 0-3. |
| **Space** | Pause or resume. |
| **T** | Toggle 1x / 2x speed. |
| **Hold X** | Detach the rear car after the confirmation meter fills. |
| **Up / Right / Down** | Immediately commit the upper / middle / lower route. |

All major controls also have clickable UI equivalents.

## Run structure

1. **Travel:** Balance power, supplies, lumen, repairs, movement, and defense while aiming the headlight at approaching threats.
2. **Route reveals:** Every roughly 52 seconds, inspect three projected rail branches and commit one. Offered events do not repeat until the eligible pool is exhausted.
3. **Waypost Five:** At 7,600 m, preview and undo refit decisions before committing. Buy a car, fit the fifth slot, install upgrades, repair, reorder, and assign crew.
4. **The Longshadow:** At 14,500 m, survive readable minimum-length phases: hold the Veil in the beam, follow the Tether, then time Focus against the Charge.
5. **Dawn Beacon:** After the boss falls, complete the final 300 m and review the Dawn Ledger.

A typical 1x run lasts about 8-13 minutes. Defeat occurs when locomotive integrity reaches zero or the crew remains without supplies long enough for the train to fail.

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
& "C:\Users\bradleywo\Tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path .
```

The deterministic suite covers save migration, malformed-save rejection, priority clamping, brownout recovery, station previews and undo, field actions, route uniqueness and chain effects, crew loss and evacuation, Focus geometry, manual salvos, hold-to-detach, boss pacing and resume, three complete strategy archetypes, and a six-seed balance sweep. The reference campaigns finish in approximately 11-13 simulated minutes.

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
