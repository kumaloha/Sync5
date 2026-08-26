# Expansion 200 Quiet Glyph Design

**Date:** 2026-08-25

**Status:** Approved

## Goal

Create reserve expansion assets that bring the catalog to 200 Jokers and 100
Blinds while preserving the approved Quiet Glyph style and making every new
asset perceptually distinct from all existing and newly generated assets.

## Scope

- Existing: 63 Jokers and 33 Blinds.
- New expansion: 137 Jokers and 67 Blinds.
- Combined target: 200 Jokers and 100 Blinds.
- The expansion package is asset/catalog only and is not connected to runtime
  mechanics or balance tables.

## Catalog structure

### Joker families

Seventeen families contain eight cards each; one independent legendary card
brings the Joker expansion total to 137.

1. pair architecture;
2. sequences and gaps;
3. suit relations;
4. cache structure;
5. discard behavior;
6. swap behavior;
7. time windows;
8. coins and holdings;
9. shops and offers;
10. persistent growth;
11. phrase/section position;
12. repetition and variation;
13. deck editing;
14. rank and face-card rules;
15. wild/copy/transform effects;
16. risk and self-restriction;
17. score-shape and settlement effects.

### Blind families

Eight families contain eight Blinds each; three independent finale bosses bring
the Blind expansion total to 67.

1. deadline pressure;
2. action lockouts;
3. hidden information;
4. cache disruption;
5. deck/rank/suit pressure;
6. score/target pressure;
7. hand-history and ordering pressure;
8. economy/shop/section pressure;
9. three finale bosses with unrelated silhouettes.

## Per-asset catalog contract

Every record contains:

- unique ASCII `id` not present in the current manifest;
- Chinese and English names;
- family, kind, and rarity/tier;
- one-line reserve mechanic in Chinese and English;
- literal visual metaphor;
- base silhouette;
- modifier;
- orientation;
- negative-space pattern;
- encoded count;
- `uniqueness_key` combining those visual fields;
- image-generation subject prompt.

## Visual differentiation

- No two new assets may share a `uniqueness_key`.
- No new ID may collide with an existing ID.
- Family resemblance comes from the base silhouette only; variants change at
  least two of modifier, direction, count, or negative space.
- A perceptual-hash Hamming distance check rejects byte-different but visually
  near-identical images.
- Final 150px contact sheets are reviewed with names hidden first, then with
  labels to locate confusing pairs.
- Confusing pairs are regenerated until no blocking pair remains.

## Quiet Glyph rendering

- 1024×1024 PNG on `#030308`.
- All meaningful geometry inside the central `y=312..711` band.
- Joker subject at most 650×230; Blind subject at most 520×200.
- One grouped silhouette plus at most one modifier.
- Flat muted color, dark fill, thick outline, weak halo.
- No glass, bright cores, scenes, characters, prose, particle fields, or
  decorative rays.
- Standard playing-card ranks are allowed only when they are the rule.
- Blind assets use muted dark red and no secondary color.

## Isolation

- Package root: `assets/expansion_20260825_quiet_200/`.
- New images live under `jokers/` and `blinds_concept/`.
- Catalog parts and the merged catalog live under `catalog/`.
- Existing Quiet Glyph assets and all runtime assets remain unchanged.

## Acceptance criteria

- Exactly 137 new Joker PNGs and 67 new Blind PNGs.
- Combined-count metadata reports 200 Jokers and 100 Blinds.
- All IDs and uniqueness keys are unique across base and expansion catalogs.
- All masters decode as 1024×1024 PNGs.
- Zero strong subject pixels outside the safe band.
- Zero byte-identical duplicate images.
- No perceptual near-duplicate below the chosen Hamming-distance threshold.
- Expansion-wide 150px visual audit returns PASS.

