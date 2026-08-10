# Sync5 Design Source of Truth

This file records current approved product and visual decisions. Detailed
mechanic rationale remains in `design/`; implementation details remain in
`design/tech.md`.

## Product identity

Sync5 is a fast poker-deckbuilder staged as a cyberpunk live performance. The
player should feel that they are operating musical equipment under pressure,
not reading a conventional card table.

The stable visual language is:

- dark club stage;
- translucent glass modules;
- cyan, magenta, violet, and gold neon;
- audio equipment, scanning grids, and signal feedback;
- paper playing cards contrasted against dark/neon Joker and Blind modules.

## Information hierarchy

During a timed phrase, information must answer in this order:

1. What is the immediate target or threat?
2. What action or condition changes the result?
3. What is the resulting number?
4. Only then: identifiers, rarity, history, and flavor.

Decorative detail must never occupy space without also helping recognition or
state feedback.

## Approved Joker and Blind visual system — 2026-08-10

The existing cyberpunk/glass/neon shell is retained. The redesign changes the
content inside that shell:

- Every Joker and active Blind face has one unique vector fingerprint.
- Fingerprints depict the mechanic directly; generic EQ bars and interchangeable
  glyphs are not acceptable.
- At thumbnail scale, two cards must remain distinguishable with their names
  covered.
- The bottom summary uses `action/condition + result`; long explanations move
  to hover, draft detail, or the collection view.
- Frame color has one responsibility: Target/Common cyan, Uncommon violet,
  Rare gold, Blind magenta.
- Ornament is a material layer. Scan grids, reflections, glints, and technical
  codes may support the shell but cannot compete with the fingerprint.

Canonical visual asset:
`assets/design/joker_blind_visual_system.html`.

### State language

- Idle: stable silhouette at restrained glow.
- Near trigger: only the relevant segment illuminates.
- Triggered: brief white-core pulse followed by the result entering the settle
  chain.
- Suppressed by a Blind: silhouette remains visible under a broken-signal scan,
  communicating “present but disabled.”

## Current design boundary

This approval covers visual presentation only. Joker and Blind mechanics are
designed and approved separately. A visual fingerprint must follow the final
mechanic; it must not constrain or silently redefine gameplay.

## Related documents

- `design/ui_meta.md` — current screen hierarchy and layout history.
- `design/jokers.md` — current Joker mechanics and balance rationale.
- `design/blinds.md` — current Blind mechanics, proof lanes, and balance gates.
- `design/tech.md` — runtime architecture and asset/rendering conventions.
