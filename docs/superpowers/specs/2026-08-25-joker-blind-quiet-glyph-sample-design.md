# Joker + Blind Quiet Glyph Sample Design

**Date:** 2026-08-25

**Status:** Direction A approved; sample set awaiting visual approval

## Goal

Replace the bright, illustration-like v2 treatment with quiet mechanic glyphs
that remain understandable without competing with cards, scores, or timers.

## Sample scope

Generate a new isolated ten-asset sample before changing the full set:

- Jokers: `twin`, `shortcut`, `tipjar`, `finale`, `chord`, `wrecker`.
- Blinds: `norepeat`, `smallstage`, `lastcall`, `rush`.

These cover multiplier, sequence/gap, economy, time, cache, discard, repetition,
capacity restriction, action lockout, and severe time pressure.

## Visual system

### Composition

- 1024×1024 PNG master on `#030308`.
- All meaningful geometry stays inside the central `1024×400` band.
- Subject width: 55–65% of the canvas; subject height: 180–240px.
- One centered glyph; one modifier only when the mechanic cannot be expressed by
  the primary silhouette alone.
- No scenes, decorative framing, rays, particle fields, or repeated ornaments.

### Rendering

- Flat dark fill or outline-only geometry; no glass rendering.
- Primary outline at least 10px at master size.
- One muted primary color per asset; secondary color is optional and limited to
  25% of the visible area.
- Glow is a soft 12–18px halo at no more than 18% opacity.
- No white-hot cores, rainbow gradients, specular flares, or bloom bursts.
- No prose or numeric bonus labels. Standard playing-card rank glyphs remain
  allowed when they are the mechanic.

### Color and prominence

- Joker multiplier/structure glyphs: muted violet or cyan.
- Joker score/economy glyphs: muted cyan or subdued gold.
- Blind glyphs: muted dark red only; no magenta highlights.
- At 150px width, the glyph must be readable but visually quieter than the card
  name, score, and timer.

## Ten sample metaphors

- `twin`: one pair of overlapping equal-rank cards; a small second pair notch is
  the only modifier.
- `shortcut`: one straight ribbon with a single gap bridged by a short arrow.
- `tipjar`: one untouched hand silhouette with two small coin circles beneath.
- `finale`: one clock outline with only the final wedge marked.
- `chord`: one three-slot cache tray filled by the same suit.
- `wrecker`: three discard ticks aimed at one completed-hand silhouette.
- `norepeat`: one repeat loop crossed by a slash.
- `smallstage`: one cache tray compressed to two slots.
- `lastcall`: one clock with the final wedge blocking a discard mark.
- `rush`: one six-wedge clock compressed by two inward bars.

## Isolation and delivery

- Create `assets/redesign_20260825_quiet_sample/`.
- Keep v1, v2, and runtime asset directories unchanged.
- Include `jokers/`, `blinds_concept/`, `contact_sheets/`, `manifest.json`, and
  `README.md`.

## Acceptance criteria

- Exactly ten expected PNGs, each 1024×1024.
- Zero strong subject pixels outside the central safe band.
- One grouped subject plus at most one modifier.
- No particle field, prose, wrong numeric value, glass shine, or bright burst.
- Central crop remains legible at 150px width.
- A side-by-side sheet demonstrates lower luminance and lower detail density than
  v2 while preserving mechanic recognition.

