# Sync5 Game Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and validate an App Store-ready v3 master that reads as a complete colored icon tile, plus a separate rounded iOS preview.

**Architecture:** Use the built-in image-editing path with v2 as the edit target, preserving its card-first emblem while replacing the black outer field with a full-bleed violet-blue background. Save the opaque square v3 master beside earlier versions, then render a separate rounded-mask preview for visual review and validate both artifacts.

**Tech Stack:** Built-in image generation, PNG, HTML/CSS mask preview, headless Chrome, local image metadata inspection, visual review

---

### Task 1: Generate the v3 App Store master

**Files:**
- Edit target: `assets/app_icon/sync5-game-icon-master-v2.png`
- Create: `assets/app_icon/sync5-game-icon-master-v3.png`

- [x] **Step 1: Generate one square revision**

Use the built-in image-generation tool with the exact prompt below:

```text
Use case: precise-object-edit
Asset type: mobile and desktop game launcher icon master
Input images: Image 1 is the edit target and style reference
Primary request: Keep the existing two-card and small-record emblem recognizable, but redesign the presentation as a complete App Store icon tile instead of a floating logo on black.
Scene/backdrop: an opaque full-bleed dark violet-to-deep-blue gradient that reaches every canvas edge; subtle cyan and magenta illumination behind the emblem; no empty black outer field
Subject: two rounded-rectangle playing cards with pale lightly reflective paper faces, fanned and overlapping; show one large cyan spade and one large magenta heart on the exposed faces; place one glossy black vinyl record partially hidden behind the cards at lower right
Style/medium: premium polished stylized 3D game icon, clean geometry, bold silhouette, minimal detail
Composition/framing: centered square composition designed for an iOS rounded-square mask; emblem occupies roughly 76 percent of the canvas; keep all essential card, suit, and record details clear of the outer 10 percent; readable at 64 pixels
Lighting/mood: restrained neon rim light and bloom, crisp card edges, energetic cyberpunk stage mood
Color palette: dark violet #170b35 to deep blue #071d46 background, cyan #1effec, magenta #ff328d, violet #7642ff, and sparse white-hot highlights
Materials/textures: lightly reflective pale paper card faces, glossy black vinyl, crisp neon edges
Text (verbatim): ""
Constraints: change the background presentation and safe-area scale while preserving the two cards, cyan spade, magenta heart, small secondary record, polished 3D rendering, and neon-stage identity; output a full square opaque image with color through all four corners
Avoid: pure-black corners, black outer margin, floating logo presentation, baked rounded-square border or mask, transparent corners, waveform, pulse line, equalizer, music note, oversized record, words, letters, numbers, corner ranks, characters, UI, scenery, watermark, signature
```

- [x] **Step 2: Save the generated PNG in the project**

Copy the selected built-in output to:

```text
assets/app_icon/sync5-game-icon-master-v3.png
```

Keep v1 and v2 unchanged for comparison.

### Task 2: Create the rounded iOS preview

**Files:**
- Create temporarily: `/tmp/sync5-game-icon-ios-preview-v3.html`
- Create: `assets/app_icon/sync5-game-icon-ios-preview-v3.png`

- [x] **Step 1: Create the deterministic preview wrapper**

Create `/tmp/sync5-game-icon-ios-preview-v3.html` with this content, replacing
the image path only if the worktree location changes:

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
  <img src="file:///Users/kuma/Projects/Sync5/.worktrees/sync5-game-icon/assets/app_icon/sync5-game-icon-master-v3.png">
</body>
</html>
```

- [x] **Step 2: Render the rounded preview**

Run:

```text
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --allow-file-access-from-files --default-background-color=00000000 --force-device-scale-factor=1 --window-size=1024,1024 --screenshot=assets/app_icon/sync5-game-icon-ios-preview-v3.png file:///tmp/sync5-game-icon-ios-preview-v3.html
```

Expected result: a 1024×1024 PNG with transparent corners used only as a visual
approximation of the iOS system mask.

### Task 3: Validate the deliverables

**Files:**
- Verify: `assets/app_icon/sync5-game-icon-master-v3.png`
- Verify: `assets/app_icon/sync5-game-icon-ios-preview-v3.png`

- [x] **Step 1: Verify file properties**

Confirm both images are readable 1024×1024 PNG files. Confirm the upload master
uses sRGB and has no alpha channel; confirm the preview has an alpha channel.

Expected result:

```text
master: PNG image data, 1024 x 1024, RGB, no alpha, sRGB
preview: PNG image data, 1024 x 1024, RGBA
```

- [x] **Step 2: Review the full-size master**

Check that the gradient reaches every edge and corner, the image reads as a
complete colored tile, the two cards remain primary, and the record remains
secondary.

- [x] **Step 3: Review the rounded preview**

Check that the rounded preview visibly reads as an iOS app icon and that the mask
does not crop the cards, suits, or record.

- [x] **Step 4: Review launcher-scale readability**

Inspect a 64×64 rendering of the rounded preview. Two card rectangles plus the
spade and heart must remain recognizable before the record.

- [x] **Step 5: Iterate only if a requirement fails**

If validation fails, make one targeted generation edit addressing the failed requirement, replace only the unapproved master, and repeat all validation steps.

- [x] **Step 6: Report the artifacts**

Return the rounded preview inline and link both saved paths. State clearly that
the square opaque master is the App Store/Xcode source and the rounded image is
for visual review only.
