# Joker + Blind visual redesign — 2026-08-24

This directory is an isolated review package. It does not replace or modify the
current runtime assets in `assets/jokers/` or `assets/blinds/`.

## Contents

- `jokers/`: 63 generated Joker illustrations, named `joker_<id>.png`.
- `blinds_concept/`: 33 generated Blind concept icons, named `blind_<id>.png`.
- `contact_sheets/`: full-set review sheets for both families.
- `manifest.json`: expected IDs, counts, dimensions, and delivery stage.
- `reports/`: generation-batch provenance and review notes.

All final source images are 1024×1024 PNGs. The Blind images are concept-stage
assets; after art approval they still need the prompt package's final
monochrome-outline pass before runtime integration at fingerprint size.

## Visual grammar

- Joker cards use colorful cyan, pink, violet, and gold neon objects on black.
- Blind icons use red/magenta warning silhouettes with much simpler geometry.
- Multiplier effects share fanned-card glow; additive effects share plus-shaped
  particles; economy effects use gold coins; time effects use clocks; discard
  effects use flying-card trails; cache effects use violet slots; restrictions
  use red locks, gates, or slashes.

## Motif families

- Multiplier/fanned cards: `twin`, `stair`, `mono`, `triplet`, `chorus`,
  `momentum`, `glowstick`, `bassline`, `mirror`, `kaleido`, `reprise`,
  `superfan`, `shredder`, `opener`, `duet`, `triplebill`, `boxseats`, `skint`,
  `curtain`, `stopwatch`, `rebrand`, `wrecker`.
- Additive/plus particles: `encore`, `finale`, `turnover`, `chord`, `neonsign`,
  `popup`, `variation`, `fullcast`, `rainbow`, `nopair`, `rehearsal`,
  `warmtone`, `cooltone`, `undertone`, `duo`, `triad`, `stilllife`, `segue`,
  `stageexit`, `earlyout`, `digger`, `collector`.
- Economy/coins: `lonewolf`, `tipjar`, `interest`, `superfan`, `backer`,
  `royalty`, `skint`, `sponsor`.
- Time/clocks: `finale`, `momentum`, `glowstick`, `shredder`, `opener`, `freeze`,
  `curtain`, `stopwatch`, `earlyout`, plus the `rush`/`overtime`/`teardown`/
  `closing` Blind family.
- Discard/flying cards: `turnover`, `vinyl`, `bassline`, `stageexit`, `earlyout`,
  `wrecker`.
- Cache/violet slots: `chord`, `rehearsal`, `bench`, `boxseats`, `stilllife`,
  `segue`, and cache-related Blinds.
- Restriction/red locks and gates: the Blind set, especially `lastcall`,
  `lockup`, `onetake`, `oneswap`, `handseal`, `doubleseal`, `ration`, and the
  tier-4 clock family.

## QA performed

- Exact ID coverage: 63 Jokers and 33 Blinds, no missing or extra files.
- File integrity: every image opens as a PNG and is exactly 1024×1024.
- Duplicate check: no byte-identical images.
- Full contact-sheet review at thumbnail size.
- Forty-eight text-heavy, misleading-value, or over-detailed outputs were edited
  or regenerated with the image generation model across three review passes.
- The old runtime asset directories were left untouched.
