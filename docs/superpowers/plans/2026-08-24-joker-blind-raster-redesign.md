# Joker and Blind Raster Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a complete isolated 2026-08-24 raster redesign of 63 Joker illustrations and 33 Blind concept icons from the user-approved prompt package, without overwriting current runtime assets.

**Architecture:** Treat the attached prompt package and `docs/design/art_prompts_gpt.md` as the visual source of truth. Generate each asset independently with the built-in image generation model, then place outputs under a versioned root so old assets and Godot imports stay untouched. Maintain a machine-readable manifest with each ID, file path, mechanic, visual metaphor, and generation status; validate dimensions, counts, naming, and cross-card motif consistency before handoff.

**Tech Stack:** Built-in image generation model, PNG assets, shell-based metadata inspection, JSON manifest.

---

### Task 1: Create the isolated delivery structure

**Files:**
- Create: `assets/redesign_20260824/jokers/`
- Create: `assets/redesign_20260824/blinds_concept/`
- Create: `assets/redesign_20260824/manifest.json`
- Create: `assets/redesign_20260824/README.md`

- [ ] Create only the versioned directories above; do not write into `assets/jokers/` or `assets/blinds/`.
- [ ] Record the 63 Joker IDs and 33 Blind IDs from `docs/design/art_prompts_gpt.md` in `manifest.json`.
- [ ] Document that the Blind outputs are 1024px concept icons and still require a later approved monochrome-outline pass before runtime integration.

### Task 2: Generate the 63 Joker illustrations

**Files:**
- Create: `assets/redesign_20260824/jokers/joker_<id>.png`
- Modify: `assets/redesign_20260824/manifest.json`

- [ ] Generate one 1024x1024 PNG per Joker ID with the built-in image model.
- [ ] Start every request from the approved neon-glass, black-background, centered-subject visual grammar.
- [ ] Encode the rule in one poker-native subject, with no card frame, no prose, no characters, no watermark, and at least 12% safe margin.
- [ ] Keep family motifs stable: fanned glowing cards for multipliers, plus particles for additive scoring, gold coins for economy, clocks for time, flying cards for discards, violet three-slot cache trays for cache mechanics, and red locks/slashes for restrictions.
- [ ] Copy each selected model output into the exact isolated destination path and update its manifest status.

### Task 3: Generate the 33 Blind concept icons

**Files:**
- Create: `assets/redesign_20260824/blinds_concept/blind_<id>.png`
- Modify: `assets/redesign_20260824/manifest.json`

- [ ] Generate one 1024x1024 PNG per Blind ID with the built-in image model.
- [ ] Use a red/magenta warning-symbol language distinct from the colorful Joker illustrations.
- [ ] Restrict every icon to one bold central symbol, thick vector-like outline, black background, no card frame, no prose, no watermark, and at least 18% safe margin.
- [ ] Make tier escalation visible through stronger lock, slash, clock, or obstruction treatment while preserving the family silhouette.
- [ ] For the five unused Blinds, derive a literal single-symbol concept from the English and Chinese names without inventing runtime mechanics.

### Task 4: Validate and package the delivery

**Files:**
- Modify: `assets/redesign_20260824/manifest.json`
- Modify: `assets/redesign_20260824/README.md`

- [ ] Verify exactly 63 Joker PNGs and 33 Blind PNGs exist and every expected ID has exactly one file.
- [ ] Verify all PNGs are square and 1024x1024; reject corrupt or mismatched outputs.
- [ ] Produce contact sheets for visual inspection without modifying the source PNGs.
- [ ] Run the prompt-package self-check: rule readability, family motifs, strength comparability, confusing pairs, and Joker/Blind language separation.
- [ ] Regenerate any missing, corrupt, text-heavy, framed, duplicate-looking, or semantically misleading asset.
- [ ] Record remaining subjective risks in `README.md`; do not integrate the new assets into runtime paths until the user approves the isolated set.

