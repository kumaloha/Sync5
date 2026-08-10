# Joker and Blind Visual Recognition System

**Date:** 2026-08-10

**Status:** Approved visual direction

**Scope:** Presentation only; no mechanic changes

## Problem

The existing Joker and Blind modules use the correct cyberpunk glass/neon art
direction, but their hierarchy is reversed. Large grid, waveform, reflection,
and explanatory areas dominate while many cards share the same cyan frame and
generic glyph language. Players must read instead of recognizing.

The redesign must let a returning player identify a card or Blind face in about
one second, including when it is shown at the small in-run size.

## Decision

Keep the existing shell and replace generic interior content with a mechanic-
specific visual fingerprint.

Each component contains:

1. compact name and technical identifier;
2. a single large vector fingerprint tied directly to the mechanic;
3. a compact `action/condition + result` summary;
4. optional detail outside the timed-play surface.

No character illustration, new theme, or decorative card-art system is added.

## Asset contract

The canonical catalogs are:

- `assets/design/joker_blind_visual_system.html` for all 23 Jokers and the
  shared card language;
- `assets/design/blind_card_ui.html` for the final 25 pressure Blinds and four
  finale boons.

The Blind catalog supersedes the earlier 13-face exploration still visible in
the combined contact sheet. It contains the approved labels, colors, mechanic
fingerprints, and main/sub-mechanic explanation for every final entry.

Implementations may convert the vectors to Godot draw calls or individual SVG
textures. Conversion must preserve:

- outer silhouette;
- dominant direction and negative space;
- primary/secondary stroke relationship;
- mechanic-to-symbol mapping;
- legibility at the current in-run size.

## Color roles

| Component | Frame/accent |
|---|---|
| Target Joker | Cyan with a small magenta secondary channel |
| Common Support | Cyan |
| Uncommon Support | Violet |
| Rare Support | Gold |
| Blind face | Magenta |
| Positive finale boon | Gold |

Color supplements shape; it never replaces shape as the identifier.

## Space budget

The intended hierarchy is approximately:

- 20% header and system metadata;
- 50–55% unique fingerprint;
- 25–30% mechanic summary;
- decorative material uses existing layers and receives no dedicated content
  block.

Remove the mirrored reflection below Joker cards unless later visual comparison
proves that it improves state feedback without reducing legibility.

## Interaction states

| State | Required response |
|---|---|
| Idle | Stable low-glow fingerprint |
| Trigger approaching | Relevant segment lights progressively |
| Triggered | 140 ms white-core flash; result leaves card toward settle chain |
| Suppressed | Broken-signal scan while the silhouette remains identifiable |
| Unaffordable draft | Reduce shell brightness, retain fingerprint contrast |

Animations must never change the identifying silhouette.

## Acceptance criteria

- With names hidden, every Joker is distinguishable from the other Jokers at
  the current rack size.
- With names hidden, all 25 pressure Blinds and four finale boons are
  distinguishable from one another.
- A card's trigger and result are readable without parsing an English sentence.
- Existing stage, glass, neon, and audio-equipment identity remains recognizable.
- All numeric labels are sourced from game data; the view does not hardcode
  balance values.
- Disabled, near-trigger, and triggered states remain distinguishable without
  relying on color alone.

## Non-goals

- changing Joker or Blind mechanics;
- replacing the existing stage layout;
- adding generated raster illustration;
- changing playing-card visuals;
- deciding final effect balance.

## Risks

- Too many glow layers can erase the fingerprint at small size.
- Rarity color can be confused with mechanic meaning if reused elsewhere.
- Text summaries can drift from data unless derived from the same source.
- A visually attractive symbol can become misleading after mechanic changes;
  mechanic approval therefore precedes final runtime integration.
