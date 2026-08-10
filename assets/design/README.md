# UI design assets

This directory contains approved, durable visual references. They are source
assets for implementation, not runtime screenshots.

## Joker visual system and shared language

- `joker_blind_visual_system.html` is the approved contact sheet for all
  23 Jokers and the shared glass/neon card language. Its Blind section records
  the earlier 13-face exploration and is superseded by the final Blind deck.
- Open the HTML file in a browser to inspect the full-size vectors, color
  roles, card hierarchy, and state language.
- The central vector fingerprints are implementation sources. Runtime code may
  redraw the paths in Godot, but must preserve their silhouettes and meaning.

## Final Blind signal deck

- `blind_card_ui.html` is the authoritative visual catalog for the final
  8 / 8 / 8 pressure pools, fixed round-four `rush`, and four secret finale
  boons: 29 cards in total.
- Pressure Blinds always use magenta. Positive finale boons use gold. Round
  identity comes from numbering and copy, not a different frame color.
- The reviewed in-run card budget is 118×176: compact header, 68×68 mechanic
  fingerprint, and a 43px action/result summary.
- The interactive inspector contains the approved main mechanic, supporting
  mechanic, and one-sentence purpose for every card.

The approved direction retains the existing cyberpunk glass/neon shell. The
redesign is limited to information hierarchy and immediate recognition; it is
not a change of art direction.
