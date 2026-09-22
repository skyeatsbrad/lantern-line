# Step 3 audit: audiovisual vertical slice

Date: 2026-09-21

## Scope

The vertical slice establishes the remaster's first complete presentation:

- Coal-lit title composition with the remastered train silhouette.
- Layered night terrain and signal-tower silhouettes.
- Revised locomotive and opening consist rendering.
- Headlight, ash, smoke, spark, and rail movement treatment.
- Generated departure whistle and title ambience state.
- PresentationDirector integration with world and train rendering.
- Deterministic title and gameplay capture hooks.

The audit used an independent read-only review plus visual inspection of the
reference captures.

## Findings and corrections

### 1. Decorative title train competed with navigation

**Severity:** High

The first title composition placed the cab, wheels, and cars behind the
controls and utility buttons. The overlap worsened at compact resolution and
with 130% text.

**Correction:** The title rails and train were moved into the lower band and
the train scale was reduced responsively. Its highest point now remains below
the navigation block at both reference sizes.

### 2. Train labels bypassed the font and palette foundation

**Severity:** Medium

Critical labels, crew initials, and car power-state badges still used Godot's
fallback font and local color literals.

**Correction:** These surfaces now use the bundled Atkinson fonts and semantic
palette entries, including high-contrast badge text.

### 3. The title lacked an accessibility capture path

**Severity:** Medium

Gameplay capture could force the combined accessibility profile, but title
capture could only reflect the current saved settings.

**Correction:** Title capture now supports deterministic default and combined
accessibility profiles plus compact-window capture. All temporary settings are
restored before exit. Gameplay capture likewise forces a known default profile
unless the accessibility profile is requested.

### 4. Audit images and concept art entered the export pack

**Severity:** Medium

The initial Step 3 export used the project's all-resources preset, so imported
design images increased the Web PCK despite having no runtime purpose.

**Correction:** Both export presets exclude `design/*` and nested design
content. A fresh Web export contains no `design/` resource paths.

## Visual matrix

The following reference captures were generated and inspected:

- `design/captures/step3-title.png`
- `design/captures/step3-title-compact.png`
- `design/captures/step3-title-accessible.png`
- `design/captures/step3-title-compact-accessible.png`
- `design/captures/step3-gameplay.png`
- `design/captures/step3-accessible.png`

The combined accessibility profile uses 130% text, High Contrast, Reduced
Motion, Reduced Flashes, and disabled screen shake.

## Performance verification

The current display was operating at a 30 Hz V-Sync cap during the audit.
Untouched v0.5 reproduced the same 30 FPS result. With V-Sync disabled:

- Untouched v0.5: approximately 610-715 FPS.
- Step 3: approximately 494-589 FPS.
- Instrumented Step 3 reference:
  - 494 FPS.
  - 4.16 ms process monitor value.
  - 1.98 ms average sampled frame time.
  - 322 draw calls.
  - 1,554 rendered objects.
  - 24,811 primitives.
  - 135 nodes.
  - 33 resources.

The slice remains far above the locked 60 FPS desktop and 30 FPS compact
requirements.

## Regression and package verification

- Full deterministic smoke suite: passed.
- Audio generation: reproduced byte-for-byte.
- Web export: passed.
- Web PCK:
  - v0.5 baseline: 362,080 bytes.
  - Step 3 after design exclusion: 700,028 bytes.
  - Growth: 337,948 bytes.
- Exported PCK contains no `design/` paths.
- `git diff --check`: passed.

An auditor reported a transient 4/6 seed sweep in its isolated environment.
Repeated direct project runs completed 6/6 with the established deterministic
outcomes, so no reproducible simulation regression was present.

## Verdict

**Approved.** The vertical slice establishes the intended visual and audio
language without changing simulation outcomes or violating accessibility,
performance, or package budgets. Step 4 may begin.

