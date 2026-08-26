# Expansion 200 Quiet Glyph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce an isolated expansion catalog and 204 Quiet Glyph assets, raising totals to 200 Jokers and 100 Blinds with enforced visual differentiation.

**Architecture:** Draft catalog slices independently, merge and validate IDs/visual signatures before generating any image, then issue one built-in image-generation call per asset. Normalize outputs into the established safe band and brightness envelope; use exact, perceptual, and visual duplicate checks before approval.

**Tech Stack:** Built-in image generation model, JSON catalogs, PNG, Pillow/NumPy perceptual checks.

---

### Task 1: Create expansion package and catalog slices

**Files:**
- Create: `assets/expansion_20260825_quiet_200/catalog/jokers_01_06.json`
- Create: `assets/expansion_20260825_quiet_200/catalog/jokers_07_12.json`
- Create: `assets/expansion_20260825_quiet_200/catalog/jokers_13_17_legend.json`
- Create: `assets/expansion_20260825_quiet_200/catalog/blinds_01_04.json`
- Create: `assets/expansion_20260825_quiet_200/catalog/blinds_05_08_finale.json`

- [ ] Draft exactly 137 Joker and 67 Blind records with complete catalog fields.
- [ ] Avoid every existing ID and assign a unique visual-signature tuple.

### Task 2: Merge and validate the catalog

**Files:**
- Create: `assets/expansion_20260825_quiet_200/catalog/catalog.json`
- Create: `assets/expansion_20260825_quiet_200/catalog/validation.json`

- [ ] Validate counts, schema, ASCII IDs, existing-ID collisions, new-ID collisions, name collisions, uniqueness-key collisions, and family counts.
- [ ] Reject vague metaphors or prompts containing unsupported prose, scenes, characters, or more than two grouped elements.

### Task 3: Generate 137 expansion Jokers

**Files:**
- Create: `assets/expansion_20260825_quiet_200/jokers/joker_<id>.png`

- [ ] Generate one independent image per catalog record.
- [ ] Preserve each record's unique silhouette, modifier, orientation, gap, and count.
- [ ] Use the approved quiet Joker rendering envelope.

### Task 4: Generate 67 expansion Blinds

**Files:**
- Create: `assets/expansion_20260825_quiet_200/blinds_concept/blind_<id>.png`

- [ ] Generate one independent image per catalog record.
- [ ] Use one dark-red composite warning symbol with no character silhouette.

### Task 5: Normalize and build review surfaces

**Files:**
- Create: `assets/expansion_20260825_quiet_200/contact_sheets/jokers_150.png`
- Create: `assets/expansion_20260825_quiet_200/contact_sheets/blinds_150.png`
- Create: `assets/expansion_20260825_quiet_200/contact_sheets/jokers_band.png`
- Create: `assets/expansion_20260825_quiet_200/contact_sheets/blinds_band.png`

- [ ] Normalize without stretching into the safe-band subject boxes.
- [ ] Cap brightness to the approved Quiet Glyph envelope.
- [ ] Build labeled and hidden-label 150px review sheets.

### Task 6: Run differentiation and completion checks

**Files:**
- Create: `assets/expansion_20260825_quiet_200/reports/safe_band.json`
- Create: `assets/expansion_20260825_quiet_200/reports/perceptual_similarity.json`
- Create: `assets/expansion_20260825_quiet_200/manifest.json`
- Create: `assets/expansion_20260825_quiet_200/README.md`

- [ ] Verify 137+67 images, 1024×1024 dimensions, zero strong outside-band pixels, zero byte duplicates, and no perceptual near-duplicates.
- [ ] Review every 150px sheet for confusion, text, characters, excess detail, and low legibility; regenerate blockers.
- [ ] Obtain independent artifact and completion approval.

