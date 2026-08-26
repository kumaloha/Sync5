# Joker and Blind Quiet Glyph Sample Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and validate ten isolated quiet-glyph samples for the approved Direction A.

**Architecture:** Generate ten independent 1024×1024 images with the built-in image model, normalize each grouped glyph proportionally into the central 1024×400 safe band, and compare exact 150px crops against v2. Store all artifacts under `assets/redesign_20260825_quiet_sample/` and leave previous packages and runtime assets unchanged.

**Tech Stack:** Built-in image generation model, PNG, Pillow/NumPy validation, JSON manifest.

---

### Task 1: Create the isolated sample package

**Files:**
- Create: `assets/redesign_20260825_quiet_sample/jokers/`
- Create: `assets/redesign_20260825_quiet_sample/blinds_concept/`
- Create: `assets/redesign_20260825_quiet_sample/contact_sheets/`
- Create: `assets/redesign_20260825_quiet_sample/manifest.json`
- Create: `assets/redesign_20260825_quiet_sample/README.md`

- [ ] Create the sample-only directory tree.
- [ ] Record the ten approved sample IDs and their metaphors.

### Task 2: Generate six quiet Joker glyphs

**Files:**
- Create: `assets/redesign_20260825_quiet_sample/jokers/joker_twin.png`
- Create: `assets/redesign_20260825_quiet_sample/jokers/joker_shortcut.png`
- Create: `assets/redesign_20260825_quiet_sample/jokers/joker_tipjar.png`
- Create: `assets/redesign_20260825_quiet_sample/jokers/joker_finale.png`
- Create: `assets/redesign_20260825_quiet_sample/jokers/joker_chord.png`
- Create: `assets/redesign_20260825_quiet_sample/jokers/joker_wrecker.png`

- [ ] Generate each asset with one flat grouped glyph, at most one modifier, one muted primary color, weak halo, no glass, particles, rays, or prose.

### Task 3: Generate four quiet Blind glyphs

**Files:**
- Create: `assets/redesign_20260825_quiet_sample/blinds_concept/blind_norepeat.png`
- Create: `assets/redesign_20260825_quiet_sample/blinds_concept/blind_smallstage.png`
- Create: `assets/redesign_20260825_quiet_sample/blinds_concept/blind_lastcall.png`
- Create: `assets/redesign_20260825_quiet_sample/blinds_concept/blind_rush.png`

- [ ] Generate each asset as one muted dark-red outline symbol with at most one modifier and no magenta highlight.

### Task 4: Normalize, compare, and verify

**Files:**
- Create: `assets/redesign_20260825_quiet_sample/contact_sheets/sample_band.png`
- Create: `assets/redesign_20260825_quiet_sample/contact_sheets/sample_150.png`
- Create: `assets/redesign_20260825_quiet_sample/contact_sheets/quiet_vs_v2.png`

- [ ] Proportionally normalize each subject into a maximum 650×230 box centered in the safe band.
- [ ] Verify exact IDs, 1024×1024 dimensions, PNG decoding, zero strong pixels outside the band, and zero duplicate hashes.
- [ ] Build band, 150px, and side-by-side v2 comparison sheets.
- [ ] Reject any sample that is brighter or more detailed than its v2 counterpart, loses mechanic readability, contains text, or exceeds two grouped elements.

