# Step 8 Release Audit

Date: September 22, 2026

Verdict: **Approved for v0.6 publication.**

## Scope

This audit covers the complete v0.6 change set from the v0.5 baseline at
`98f6e4d56b8335ad11835dbc05dcfa045588ebda`, including:

- Presentation architecture and generated visual assets.
- World, train, enemy, effect, and Longshadow rendering.
- Original music, ambience, sound effects, buses, and runtime audio mixing.
- Responsive HUD, route, station, settings, guide, and ending interfaces.
- Accessibility behavior and keyboard focus.
- Deterministic tests, runtime probes, capture harnesses, and package checks.
- Version metadata, repository screenshots, and the GitHub Pages mirror.

## Independent review

An independent final-diff review found no release-blocking or important
functional, accessibility, determinism, browser, audio, packaging, or release
defects.

The review independently confirmed:

- Godot 4.7.2 and the Compatibility renderer remain authoritative.
- Gameplay randomness remains deterministic.
- Longshadow protection timing and strategic simulation are unchanged.
- Browser audio remains silent until intentional user input.
- Accessibility settings remain independent and persistent.
- Critical information retains textual or shape-based equivalents.
- Five-car framing remains bounded at desktop and compact sizes.
- The 16-voice ceiling, two music-loop-player limit, and 1.8-second crossfade
  remain enforced.
- Font licenses are packaged while `design/` and standalone mechanical ticks
  remain excluded.
- Visible and Windows metadata identify v0.6.
- `docs/` mirrors the final Web export and preserves `.nojekyll`.

## Audit correction carried into release

The Step 7 audit found that route and station exits used the generic
0.18-second close duration instead of their authored 0.25-0.5-second band.

`UITheme.MODAL_EXIT_SECONDS` is now 0.26 seconds and is passed explicitly by
both route and station exits. The full-motion behavior is covered by regression
tests that protect the minimum and maximum timing bounds and duplicate-input
rejection.

## Deterministic regression

- Godot import and script compilation: passed.
- Source-tree smoke suite: passed.
- Exported Windows-package smoke suite: passed.
- Reference campaign: victory at 742.0 simulated seconds with 12 route
  commitments.
- Beam: victory at 741.0 seconds.
- Gunline: victory at 740.7 seconds.
- Sustain: victory at 739.0 seconds.
- Adaptive seeds 101, 202, 303, 404, 505, and 606: all victorious.

The smoke suite also protects responsive geometry, focus, warning priority,
scene fades, modal transition timing, ending reveal timing, audio limits,
browser gesture gating, and generated-asset expectations.

## Real-renderer performance

| Probe | FPS | Average frame time | Draw calls |
|---|---:|---:|---:|
| Desktop gameplay | 60 | 17.12 ms | 295 |
| Compact accessibility gameplay | 60 | 17.01 ms | 281 |
| Desktop dense combat | 59 | 17.01 ms | 424 |
| Compact accessibility dense combat | 60 | 17.04 ms | 420 |

The audio probe observed:

- 13 simultaneous voices at peak.
- 2 simultaneous music players at peak.
- A completed music crossfade.
- Dawn as the final requested and active score state.
- 3 active voices at probe completion.

## Final visual review

Fresh release captures were generated from the v0.6 source:

- 13 default captures at 1280 x 720.
- 13 accessibility captures at 960 x 540 with 130% text, High Contrast,
  Reduced Motion, Reduced Flashes, and screen shake disabled.

Both matrices cover title, early travel, dense combat, route reveal, station,
critical train damage, Longshadow Veil, Tether, and Charge, Dawn Ledger, Last
Light Ledger, boss phase banner, and maximum five-car consist.

The title identifies v0.6. Route and station actions remain readable and
keyboard-focused. Both ending actions remain visible without scrolling. The
critical train, complete consist, wheels, and Pursuer silhouette remain above
the compact HUD.

## Audio and media inventory

- 6 original music loops.
- 2 original ending stingers.
- 70 mono sound effects.
- 78 media files across 24 semantic groups.
- 5,334,291 source bytes.
- Manifest SHA-256:
  `71EE74BF014997A03D82FCC8DB9E89F1CF65733621FEB80C1CC1996D7AAD2490`.

The final audio library remains below the 8 MB source target.

## Release packages

- Web export: passed.
- Windows export: passed.
- Web PCK: 3,806,376 bytes.
- Windows PCK: 3,806,376 bytes.
- Matching SHA-256:
  `2E83F0BEC4F1BBBBD9E8C99F3AD69ABC3E7277A585F707E4E3B43EEADB13D775`.
- PCK growth from approved Step 6: 30,208 bytes.
- Windows file version: `0.6.0.0`.
- Windows product version: `0.6.0.0`.
- Windows description: `The Lantern Line v0.6`.
- Both packages include `OFL-Atkinson.txt` and `OFL-Bitter.txt`.
- Both packages exclude `design/`.
- Both packages exclude standalone mechanical-tick assets.
- The final PCK remains below the 12 MB remaster budget.

Every generated Web file was mirrored byte-for-byte into `docs/`.
`docs/index.pck` matches the release PCK hash and `docs/.nojekyll` remains
present.

## Publication verification

- Release commit:
  `61eb6a6884fff60e8634ddd7afb907662242b087`.
- Local `main` and `origin/main` matched after the release push.
- The public GitHub Pages `index.pck` downloaded as 3,806,376 bytes.
- The public PCK SHA-256 matched the audited local package:
  `2E83F0BEC4F1BBBBD9E8C99F3AD69ABC3E7277A585F707E4E3B43EEADB13D775`.
- Public `index.html`, JavaScript, WebAssembly, and PCK assets returned HTTP
  200 with the expected content types and release sizes.
- A Chromium Playwright check reached the v0.6 title screen at 1280 x 720.
- The HTML loading overlay was removed after engine startup.
- The public boot produced no browser console errors or uncaught page errors.

## Non-blocking observation

In the densest High Contrast capture, an adjacent Shadow Ward can partially
cross another enemy's supplementary text label because world labels and ward
graphics share the same draw pass. Enemy silhouettes and their required
shape-based distinctions remain fully visible, so no critical information is
lost. A future polish pass may move accessibility labels to a dedicated
foreground layer.

## Approval

The complete v0.6 release meets the authored identity, gameplay, deterministic,
accessibility, performance, browser, audio, package, and documentation
requirements. The audited build is published and verified on GitHub Pages.
