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

## Profession character art pack

- `assets/characters/manifest.json` is the authoritative art roster for the
  eight profession identities. It owns visual identity fields, selected design
  panels, palette notes, avatar crop coordinates, and the `cn` / `title` labels
  used by review tooling.
- `assets/characters/source/` stores accepted raw generation outputs:
  `<id>_portrait.png`, `<id>_walk.png`, and `<id>_dance.png`. These are source
  assets, not runtime-sized sprites.
- `assets/characters/<id>/` stores final processed assets:
  `portrait.png`, `avatar.png`, `walk.png`, `dance.png`, and `prompt.json`.
- `assets/characters/contact-sheet.png` is the roster review sheet generated
  from the manifest and final processed assets.

Regeneration and validation commands:

```bash
godot --headless --log-file /tmp/sync5-character-build.log --path . --script res://tools/art/build_character_assets.gd
godot --headless --log-file /tmp/sync5-character-validate.log --path . --script res://tools/art/verify_character_assets.gd
godot --headless --log-file /tmp/sync5-character-contact.log --path . --script res://tools/art/character_contact_sheet.gd
```

Asset dimensions:

- Portrait master: 1536x2048.
- Avatar crop: 512x512.
- Walk sheet: 1024x128, eight 128x128 frames.
- Dance sheet: 1024x128, eight 128x128 frames.
- Contact sheet: 2048x1152, four columns by two rows.

Ownership:

- Character art source, manifest identity fields, final processed character
  PNGs, prompts, and contact-sheet tooling belong to the art production lane.
- Character mechanics, gameplay data, runtime `Walker` rendering, and character
  selection integration remain owned by gameplay/runtime code.
- Runtime integration is a separate future task.
