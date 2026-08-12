# Sync5 Game Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and validate one polished 1024×1024 Sync5 launcher-icon master that fuses a playing card with a vinyl record.

**Architecture:** Use the built-in image-generation path to create one raster master from the approved visual specification. Save the selected result in the project, then validate its dimensions, visual content, palette, safe-area composition, and readability at launcher scale before delivery.

**Tech Stack:** Built-in image generation, PNG, local image metadata inspection, visual review

---

### Task 1: Generate the master icon

**Files:**
- Create: `assets/app_icon/sync5-game-icon-master.png`

- [ ] **Step 1: Generate one square master**

Use the built-in image-generation tool with the exact prompt below:

```text
Use case: stylized-concept
Asset type: mobile and desktop game launcher icon master
Primary request: Create one iconic emblem that fuses a playing card with a vinyl record for the cyberpunk poker-deckbuilder Sync5.
Scene/backdrop: pure near-black background; no environment or scenery
Subject: one slightly tilted dark translucent-glass playing card as the dominant silhouette, with one glossy black vinyl record physically integrated into or emerging from the card; the record center is the focal point; include only two or three broad grooves and one compact waveform pulse that visually joins the card and record
Style/medium: premium polished stylized 3D game icon, clean geometry, bold silhouette, minimal detail
Composition/framing: centered square composition, generous safe-area padding for rounded launcher masks, emblem fills roughly 72 percent of the canvas, readable at 64 pixels
Lighting/mood: restrained neon rim light and bloom, bright controlled center highlight, energetic cyberpunk stage mood
Color palette: black base with cyan #1effec, magenta #ff328d, violet #7642ff, and sparse white-hot highlights
Materials/textures: dark glass card, glossy black vinyl, crisp neon edges
Text (verbatim): ""
Constraints: exactly one card and one record fused into a single emblem; black background; all visible light comes from the emblem; preserve a clear card silhouette and clear circular record silhouette
Avoid: words, letters, numbers, playing-card suits, characters, faces, UI, badges, extra objects, scenery, border frames, busy micro-detail, washed-out glow, pale background, watermark, signature
```

- [ ] **Step 2: Save the generated PNG in the project**

Copy the selected built-in output to:

```text
assets/app_icon/sync5-game-icon-master.png
```

Do not overwrite another asset with a different name.

### Task 2: Validate the deliverable

**Files:**
- Verify: `assets/app_icon/sync5-game-icon-master.png`

- [ ] **Step 1: Verify file properties**

Confirm the image is a readable PNG with dimensions exactly 1024×1024.

Expected result:

```text
PNG image data, 1024 x 1024
```

- [ ] **Step 2: Review the full-size image**

Check that the result contains one fused card-and-record emblem, no text or watermark, a near-black background, the approved cyan/magenta/violet palette, and safe padding on all sides.

- [ ] **Step 3: Review launcher-scale readability**

Inspect a 64×64 rendering. The card outline and record circle must remain separately recognizable, while the waveform remains a secondary accent.

- [ ] **Step 4: Iterate only if a requirement fails**

If validation fails, make one targeted generation edit addressing the failed requirement, replace only the unapproved master, and repeat all three validation steps.

- [ ] **Step 5: Report the artifact**

Return the final image inline and link the saved master path. State that platform-specific Android or iOS derivatives are outside this master-generation step.
