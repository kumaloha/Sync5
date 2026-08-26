# Joker and Blind Raster Redesign v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate a new isolated 63-Joker and 33-Blind asset set that obeys the v2 central 1024×400 safe-band, horizontal-layout, two-element, and 150px-legibility requirements.

**Architecture:** Use `docs/design/art_prompts_gpt.md` and the attached v2 prompt package as the approved source of truth. Generate each 1024×1024 asset independently with the built-in image model, writing only to `assets/redesign_20260824_v2/`. Verify the full square, central crop, and 150px crop separately so the package is both reviewable and compatible with the existing source-to-runtime pipeline.

**Tech Stack:** Built-in image generation model, PNG, Pillow-based contact-sheet and pixel-bound checks, JSON manifest.

---

### Task 1: Create the isolated v2 package

**Files:**
- Create: `assets/redesign_20260824_v2/jokers/`
- Create: `assets/redesign_20260824_v2/blinds_concept/`
- Create: `assets/redesign_20260824_v2/contact_sheets/`
- Create: `assets/redesign_20260824_v2/manifest.json`
- Create: `assets/redesign_20260824_v2/README.md`

- [ ] Create only the v2 directory tree and leave `assets/redesign_20260824/`, `assets/jokers/`, and `assets/blinds/` untouched.
- [ ] Record all 63 Joker and 33 Blind IDs plus their mechanics, metaphors, paths, and v2 review status.

### Task 2: Generate 63 horizontal Joker masters

**Files:**
- Create: `assets/redesign_20260824_v2/jokers/joker_<id>.png`

- [ ] Generate one independent 1024×1024 PNG per Joker with all required subject geometry inside y=312..711.
- [ ] Use a horizontal fan, row, or symmetric arrangement with one subject and at most one modifier.
- [ ] Use thick outlines, no prose or bonus-number labels, no card frame, and no essential detail outside the safe band.
- [ ] Keep effect-family motifs consistent and encode strength through amount/brightness rather than unrelated objects.

### Task 3: Generate 33 simplified Blind concepts

**Files:**
- Create: `assets/redesign_20260824_v2/blinds_concept/blind_<id>.png`

- [ ] Generate one independent 1024×1024 PNG per Blind with one red/magenta warning silhouette inside y=312..711.
- [ ] Limit each icon to one symbol or one symbol plus a lock/slash/clock modifier.
- [ ] Keep the silhouette thick enough to survive a 150px-wide central-crop preview and later monochrome-outline conversion.

### Task 4: Build previews and run v2 validation

**Files:**
- Create: `assets/redesign_20260824_v2/contact_sheets/jokers_full.png`
- Create: `assets/redesign_20260824_v2/contact_sheets/blinds_full.png`
- Create: `assets/redesign_20260824_v2/contact_sheets/jokers_band.png`
- Create: `assets/redesign_20260824_v2/contact_sheets/blinds_band.png`
- Create: `assets/redesign_20260824_v2/contact_sheets/jokers_150.png`
- Create: `assets/redesign_20260824_v2/contact_sheets/blinds_150.png`

- [ ] Verify exact ID coverage, 1024×1024 dimensions, valid PNG decoding, and zero byte-identical duplicates.
- [ ] Crop every master to the central 1024×400 band and build contact sheets from those crops.
- [ ] Resize every central crop to 150px wide and build 150px review sheets.
- [ ] Detect strong non-background content outside the central band; visually review and regenerate failures.
- [ ] Flag any asset exceeding two visual elements, containing prose/bonus values, becoming unclear at 150px, or confusing its family pair.

### Task 5: Package and independently verify

**Files:**
- Modify: `assets/redesign_20260824_v2/manifest.json`
- Modify: `assets/redesign_20260824_v2/README.md`

- [ ] Record final per-asset status, family, safe-band result, and 150px review result.
- [ ] Run a fresh complete validation and an independent visual review before reporting completion.
- [ ] Keep Blind assets at concept stage and document the pending monochrome-outline approval pass.

