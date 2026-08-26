# Joker and Blind Quiet Glyph Full Set Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the approved Quiet Glyph sample into an isolated full set of 63 Jokers and 33 Blinds.

**Architecture:** Copy the ten user-approved samples unchanged, generate the remaining 86 assets independently with the built-in image model, then apply the same proportional safe-band normalization and low-luminance cap used by the sample. Build full, central-band, 150px, and v2-comparison sheets; reject complex, bright, text-bearing, or ambiguous outputs before delivery.

**Tech Stack:** Built-in image generation model, PNG, Pillow/NumPy validation, JSON manifest.

---

### Task 1: Create the full-set isolated package

**Files:**
- Create: `assets/redesign_20260825_quiet_full/jokers/`
- Create: `assets/redesign_20260825_quiet_full/blinds_concept/`
- Create: `assets/redesign_20260825_quiet_full/contact_sheets/`
- Create: `assets/redesign_20260825_quiet_full/manifest.json`
- Create: `assets/redesign_20260825_quiet_full/README.md`

- [ ] Create only the new full-set directory tree.
- [ ] Copy the six approved Joker and four approved Blind sample masters unchanged.

### Task 2: Generate the remaining 57 Joker glyphs

**Files:**
- Create: `assets/redesign_20260825_quiet_full/jokers/joker_<id>.png`

- [ ] Generate each non-sample Joker as one grouped flat glyph plus at most one modifier.
- [ ] Replace particle-based additive metaphors with one large plus symbol and bright multiplier effects with a restrained outline fan.
- [ ] Use one muted primary color, no glass, rays, particles, prose, or bonus labels.

### Task 3: Generate the remaining 29 Blind glyphs

**Files:**
- Create: `assets/redesign_20260825_quiet_full/blinds_concept/blind_<id>.png`

- [ ] Generate each non-sample Blind as one muted dark-red outline symbol plus at most one modifier.
- [ ] Prohibit characters, faces, scenes, magenta highlights, particles, and bright fills.

### Task 4: Normalize and validate

**Files:**
- Create: `assets/redesign_20260825_quiet_full/contact_sheets/jokers_full.png`
- Create: `assets/redesign_20260825_quiet_full/contact_sheets/blinds_full.png`
- Create: `assets/redesign_20260825_quiet_full/contact_sheets/jokers_band.png`
- Create: `assets/redesign_20260825_quiet_full/contact_sheets/blinds_band.png`
- Create: `assets/redesign_20260825_quiet_full/contact_sheets/jokers_150.png`
- Create: `assets/redesign_20260825_quiet_full/contact_sheets/blinds_150.png`
- Create: `assets/redesign_20260825_quiet_full/contact_sheets/quiet_vs_v2.png`

- [ ] Normalize Joker subjects into at most 650×230 and Blind subjects into at most 520×200 without stretching.
- [ ] Cap Joker highlights at 145 and Blind highlights at 112.
- [ ] Verify 63+33 IDs, 1024×1024 dimensions, zero strong pixels outside the central band, zero duplicate hashes, and lower mean luminance than v2.
- [ ] Visually audit 150px sheets for complexity, text, particle fields, and confusing pairs; regenerate every blocker.

### Task 5: Package and independently review

**Files:**
- Modify: `assets/redesign_20260825_quiet_full/manifest.json`
- Modify: `assets/redesign_20260825_quiet_full/README.md`

- [ ] Record per-asset mechanic, metaphor, status, safe-band result, 150px result, and luminance comparison.
- [ ] Obtain independent artifact and visual approval before reporting completion.

