# Sync5 Game Icon v4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and validate an App Store-ready v4 icon in which the vinyl record is physically integrated into a playing-card back rather than appearing as a separate object.

**Architecture:** Use the built-in image-editing path with v3 as the style and composition reference, replacing its three-object collage with one pale spade face card and one dark vinyl card back. Save an opaque square master, render a separate deterministic rounded iOS preview, then inspect both at full size and launcher size before running the project test suite.

**Tech Stack:** Built-in image generation, PNG, HTML/CSS mask preview, headless Chrome, local image metadata inspection, Godot test runner, visual verdict

---

### Task 1: Generate the fused card-and-vinyl master

**Files:**
- Edit target: `assets/app_icon/sync5-game-icon-master-v3.png`
- Create: `assets/app_icon/sync5-game-icon-master-v4.png`

- [ ] **Step 1: Generate one precise-object revision**

Use the built-in image-generation tool with this exact prompt:

```text
Use case: precise-object-edit
Asset type: premium mobile game launcher icon master
Input images: Image 1 is the edit target and style reference
Primary request: Redesign the central emblem so the playing-card and vinyl-record identities are physically fused into one compact two-card mark, not presented as separate adjacent props.
Scene/backdrop: retain an opaque full-bleed dark violet-to-deep-blue gradient reaching every canvas edge; subtle cyan and magenta illumination; no black margin, floor plane, pedestal, or reflection
Foreground subject: one pale rounded-rectangle playing card with one large centered cyan spade; no heart, ranks, corner symbols, or text
Rear subject: one dark rounded-rectangle playing card whose entire card-back design is physically made from glossy black vinyl grooves, a small magenta-violet center label, and a spindle point; every circular groove and highlight must be clipped inside the rounded rectangular card silhouette
Object relationship: the two cards overlap and fan as one emblem; they share the same perspective, physical thickness, bevel language, lighting, and center of gravity; the vinyl card back must unmistakably remain a rectangular playing card
Style/medium: premium polished stylized 3D game icon, clean geometry, bold silhouette, minimal detail
Composition/framing: centered square composition designed for an iOS rounded-square mask; the two-card emblem occupies roughly 76 percent of the canvas; keep essential card and spade details clear of the outer 10 percent; readable at 64 pixels
Lighting/mood: restrained cyan and magenta neon rim light with sparse bloom, crisp card edges, energetic cyberpunk stage mood
Color palette: dark violet #170b35 to deep blue #071d46 background, cyan #1effec, magenta #ff328d, violet #7642ff, glossy black, and sparse white-hot highlights
Materials/textures: lightly reflective pale paper face card and glossy black-vinyl card back, both with identical card thickness and edge construction
Text (verbatim): ""
Constraints: preserve the full-bleed colored App Store tile presentation; make the front spade card immediately readable first and the rear vinyl card identity discoverable second; output a full square opaque image with color through all four corners
Avoid: any separate circular record protruding outside a card, third object, heart suit, floor reflection, contact reflection, waveform, pulse line, equalizer, music note, words, letters, numbers, corner ranks, characters, UI, baked rounded-square border or mask, transparent corners, watermark, signature
```

- [ ] **Step 2: Save the generated PNG**

Save the selected output as:

```text
assets/app_icon/sync5-game-icon-master-v4.png
```

Keep v1 through v3 unchanged for comparison.

### Task 2: Create the rounded iOS preview

**Files:**
- Create temporarily: `/tmp/sync5-game-icon-ios-preview-v4.html`
- Create: `assets/app_icon/sync5-game-icon-ios-preview-v4.png`

- [ ] **Step 1: Create the deterministic preview wrapper**

Create `/tmp/sync5-game-icon-ios-preview-v4.html` with this content:

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    html, body {
      margin: 0;
      width: 1024px;
      height: 1024px;
      overflow: hidden;
      background: transparent;
    }
    img {
      display: block;
      width: 1024px;
      height: 1024px;
      object-fit: cover;
      border-radius: 22.37%;
    }
  </style>
</head>
<body>
  <img src="file:///Users/kuma/Projects/Sync5/.worktrees/sync5-game-icon/assets/app_icon/sync5-game-icon-master-v4.png">
</body>
</html>
```

- [ ] **Step 2: Render the rounded preview**

Run:

```text
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --allow-file-access-from-files --default-background-color=00000000 --force-device-scale-factor=1 --window-size=1024,1024 --screenshot=assets/app_icon/sync5-game-icon-ios-preview-v4.png file:///tmp/sync5-game-icon-ios-preview-v4.html
```

Expected result: a 1024x1024 RGBA PNG with transparent corners, used only to preview the iOS system mask.

### Task 3: Validate the deliverables

**Files:**
- Verify: `assets/app_icon/sync5-game-icon-master-v4.png`
- Verify: `assets/app_icon/sync5-game-icon-ios-preview-v4.png`
- Update after import: `assets/app_icon/sync5-game-icon-master-v4.png.import`

- [ ] **Step 1: Verify file properties**

Confirm both images are readable 1024x1024 PNG files. The upload master must use sRGB, RGB color, and no alpha; the preview must use RGBA with alpha.

Expected result:

```text
master: PNG image data, 1024 x 1024, RGB, no alpha, sRGB
preview: PNG image data, 1024 x 1024, RGBA
```

- [ ] **Step 2: Inspect the full-size master and rounded preview**

Check that the emblem contains exactly two overlapping card rectangles, that all vinyl geometry stays within the rear card, that no independent record or floor reflection remains, and that the mask crops no essential detail.

- [ ] **Step 3: Inspect launcher-scale readability**

Render the rounded preview at 64x64. The cyan spade and both card silhouettes must remain immediately readable; the rear card's circular sheen should suggest vinyl without replacing its rectangular silhouette.

- [ ] **Step 4: Record the visual verdict**

Apply the visual-verdict rubric and persist the result to `.omx/state/app-icon/ralph-progress.json`. A score of at least 90/100 is required. If it fails, make one targeted edit addressing only the failed criterion and repeat Tasks 2 and 3.

- [ ] **Step 5: Import and run project tests**

Run:

```text
godot --headless --path . --log-file /tmp/sync5-icon-v4-import.log --import
godot --headless --path . --log-file /tmp/sync5-icon-v4-tests.log --script res://tests/runner.gd
```

Expected result: the icon imports successfully and the test runner reports `948 passed, 0 failed`.

- [ ] **Step 6: Report the artifacts**

Return the rounded preview inline and link both saved paths. State clearly that the opaque square master is the App Store/Xcode source and the rounded image is a visual review preview only.
