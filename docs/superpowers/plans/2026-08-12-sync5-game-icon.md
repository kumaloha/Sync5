# Sync5 Game Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and validate a second 1024×1024 Sync5 launcher-icon master whose playing-card identity is unmistakable before its music cue.

**Architecture:** Use the built-in image-editing path with the first icon as a style reference, replacing its ambiguous card-record fusion with two dominant suit cards and one secondary record. Save the revision beside the first master for comparison, then validate its dimensions, hierarchy, palette, safe-area composition, and readability at launcher scale before delivery.

**Tech Stack:** Built-in image generation, PNG, local image metadata inspection, visual review

---

### Task 1: Generate the revised master icon

**Files:**
- Reference: `assets/app_icon/sync5-game-icon-master.png`
- Create: `assets/app_icon/sync5-game-icon-master-v2.png`

- [x] **Step 1: Generate one square revision**

Use the built-in image-generation tool with the exact prompt below:

```text
Use case: precise-object-edit
Asset type: mobile and desktop game launcher icon master
Input images: Image 1 is the edit target and style reference
Primary request: Redesign the emblem so it unmistakably reads as a card game first. Replace the ambiguous folder-like card and large record with two clear fanned playing cards as the dominant subject, plus one much smaller vinyl record behind their lower-right edge.
Scene/backdrop: pure near-black background; no environment or scenery
Subject: two rounded-rectangle playing cards with pale lightly reflective paper faces, fanned and overlapping; show one large cyan spade and one large magenta heart on the exposed faces; place one glossy black vinyl record partially hidden behind the cards at lower right
Style/medium: premium polished stylized 3D game icon, clean geometry, bold silhouette, minimal detail
Composition/framing: centered square composition, generous safe-area padding for rounded launcher masks; the two-card fan occupies roughly 70 percent of the canvas; the record occupies roughly 25 percent and is visibly secondary; readable at 64 pixels
Lighting/mood: restrained neon rim light and bloom, crisp card edges, energetic cyberpunk stage mood
Color palette: black base with cyan #1effec, magenta #ff328d, violet #7642ff, and sparse white-hot highlights
Materials/textures: lightly reflective pale paper card faces, glossy black vinyl, crisp neon edges
Text (verbatim): ""
Constraints: playing cards must be the first-read subject; both the spade and heart must remain visible and recognizable; preserve the original black background, cyan-magenta-violet palette, polished 3D rendering, neon rim-light quality, and launcher-safe padding
Avoid: waveform, pulse line, equalizer, music note, oversized record, folder silhouette, words, letters, numbers, corner ranks, characters, faces, UI, badges, extra objects, scenery, border frames, busy micro-detail, washed-out glow, watermark, signature
```

- [x] **Step 2: Save the generated PNG in the project**

Copy the selected built-in output to:

```text
assets/app_icon/sync5-game-icon-master-v2.png
```

Keep the first master unchanged for comparison.

### Task 2: Validate the deliverable

**Files:**
- Verify: `assets/app_icon/sync5-game-icon-master-v2.png`

- [x] **Step 1: Verify file properties**

Confirm the image is a readable PNG with dimensions exactly 1024×1024.

Expected result:

```text
PNG image data, 1024 x 1024
```

- [x] **Step 2: Review the full-size image**

Check that the two pale suit cards are the first-read subject, the smaller record stays secondary, no waveform or music note appears, no text or watermark appears, and the approved black/cyan/magenta/violet presentation and safe padding remain intact.

- [x] **Step 3: Review launcher-scale readability**

Inspect a 64×64 rendering. Two card rectangles plus the spade and heart must remain recognizable before the record.

- [x] **Step 4: Iterate only if a requirement fails**

If validation fails, make one targeted generation edit addressing the failed requirement, replace only the unapproved master, and repeat all three validation steps.

- [x] **Step 5: Report the artifact**

Return the final image inline and link the saved master path. State that platform-specific Android or iOS derivatives are outside this master-generation step.
