# Eight Profession Character Art Production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a coherent, profession-readable art pack for all eight protagonists: full portrait, avatar, eight-frame walk sheet, eight-frame dance sheet, and reproducible prompt metadata.

**Architecture:** Freeze one selected design and identity prompt per character in a manifest, then use each accepted portrait as the identity master for every derived asset. Generate animation source sheets against the portrait reference, normalize and pack them with Godot, and validate dimensions/alpha independently from gameplay. This plan does not replace the current procedural `Walker` renderer or change character mechanics.

**Tech Stack:** OpenAI ImageGen, Godot 4.6/GDScript image normalization and sprite packing, JSON, PNG with alpha, repository screenshot tooling.

---

## File map

- Create `assets/reference/characters/candidate_<id>.png`: durable copies of the eight approved three-way design sheets.
- Create `assets/characters/manifest.json`: exact roster, selected panel, identity anchors, palette, and crop data.
- Create `assets/characters/<id>/portrait.png`: 1536×2048 full-body identity master.
- Create `assets/characters/<id>/avatar.png`: 512×512 portrait crop.
- Create `assets/characters/<id>/walk.png`: one horizontal 1024×128 sheet with eight 128×128 frames.
- Create `assets/characters/<id>/dance.png`: one horizontal 1024×128 sheet with eight 128×128 frames.
- Create `assets/characters/<id>/prompt.json`: portrait/walk/dance prompts, revisions, and source hashes.
- Create `assets/characters/source/<id>_portrait.png`: accepted raw portrait generation.
- Create `assets/characters/source/<id>_walk.png`: accepted 4×2 walk source sheet.
- Create `assets/characters/source/<id>_dance.png`: accepted 4×2 dance source sheet.
- Create `assets/characters/contact-sheet.png`: portrait/avatar/walk/dance review surface.
- Create `tools/art/build_character_assets.gd`: normalizes portraits, crops avatars, keys backgrounds, and packs sprite sheets.
- Create `tools/art/verify_character_assets.gd`: validates roster, files, sizes, hashes, and alpha.
- Create `tools/art/character_contact_sheet.gd`: renders the eight-character review sheet.
- Modify `assets/design/README.md`: records ownership and non-integration status.
- Do not modify `data/characters.json`, `core/character.gd`, `view/walker.gd`, `view/pick_walker.gd`, or character mechanics in this plan.

### Task 1: Preserve approved references and freeze the character manifest

**Files:**
- Create: `assets/reference/characters/candidate_dj.png`
- Create: `assets/reference/characters/candidate_magician.png`
- Create: `assets/reference/characters/candidate_boxer.png`
- Create: `assets/reference/characters/candidate_bartender.png`
- Create: `assets/reference/characters/candidate_seer.png`
- Create: `assets/reference/characters/candidate_drummer.png`
- Create: `assets/reference/characters/candidate_rapper.png`
- Create: `assets/reference/characters/candidate_tattooist.png`
- Create: `assets/characters/manifest.json`

- [ ] **Step 1: Copy the eight reviewed candidate sheets into the repository**

Use these exact source files and stable destination names:

```text
exec-71a1952c-0d5e-40cc-86c4-90015e933175.png -> candidate_dj.png
exec-4d1e5fc9-ad6c-4c7a-afa4-b150cde0593f.png -> candidate_magician.png
exec-6a4d4bb0-026d-4dbc-9a0c-92db7e4f5027.png -> candidate_boxer.png
exec-6fb98836-4a0a-4cba-a3dd-a3c77e3f1bc5.png -> candidate_bartender.png
exec-8afad481-1013-4997-99ca-48276c2f4cef.png -> candidate_seer.png
exec-46781ecc-8817-4d01-bee6-eaacff9984f2.png -> candidate_drummer.png
exec-c4188ee3-ef95-4dba-9827-e785f7753316.png -> candidate_rapper.png
exec-2d00666b-74f7-481d-bbf6-f4f1acd3c869.png -> candidate_tattooist.png
```

Copy from `/Users/kuma/.codex/generated_images/019fe632-fdfa-76f2-850c-53239465ebcd/`. Do not crop or overwrite the originals.

- [ ] **Step 2: Create the manifest with exact top-level contract**

```json
{
  "version": 1,
  "portrait_size": [1536, 2048],
  "avatar_size": [512, 512],
  "frame_size": [128, 128],
  "frame_count": 8,
  "characters": []
}
```

Every character record must contain `id`, `idx`, `cn`, `title`, `gender_presentation`, `selected_panel`, `primary`, `secondary`, `silhouette`, `profession_prop`, `pose`, `forbid`, and `avatar_crop`.

- [ ] **Step 3: Enter this exact roster and identity contract**

| idx / id | selected panel | identity contract | palette | avatar_crop |
|---|---|---|---|---|
| 0 / dj | left | young male street DJ; lean; asymmetric short dread/mohawk silhouette; oversized distressed tech jacket; neck headphones; portable turntable; one hand on deck, relaxed forward lean | cyan `#35E8E0`, charcoal `#10141C`, small magenta | `[0.20,0.02,0.60,0.42]` |
| 1 / magician | right | young female cyber magician; tall narrow silhouette; short angular hair; projection glove; floating playing cards; fitted long coat; controlled one-hand flourish | violet `#A56BFF`, ink black, small cyan | `[0.20,0.02,0.60,0.42]` |
| 2 / boxer | center | adult male champion boxer; tallest and broadest roster member; dark skin; high-collar ring coat; oversized pink gloves; square grounded stance | hot pink `#FF4FA3`, black, small gold | `[0.20,0.01,0.60,0.40]` |
| 3 / bartender | center | adult female cyber bartender; athletic hourglass silhouette; angular orange coat tails; shaker and glowing bottles; poised mid-pour stance | orange `#FFB347`, black, small cyan | `[0.20,0.02,0.60,0.42]` |
| 4 / seer | right | adult female techno-seer; slim hooded silhouette; asymmetrical fringe; crystalline prediction interface; one hand tracing probability arcs | violet `#A56BFF`, midnight, small ice blue | `[0.20,0.01,0.60,0.42]` |
| 5 / drummer | left | young male street drummer; compact wiry build; cropped jacket; drumsticks and waist-mounted electronic pads; spring-loaded stance | cyan `#35E8E0`, dark navy, small orange | `[0.20,0.02,0.60,0.42]` |
| 6 / rapper | left | young male underground rapper; medium athletic build; cap/hood silhouette distinct from DJ; wired microphone; low center of gravity; free hand marks rhythm | magenta `#FF4FA3`, black, small cyan | `[0.20,0.02,0.60,0.42]` |
| 7 / tattooist | center | adult female tattoo artist; sturdy medium build; blunt asymmetric hair; sleeveless utility apron; tattoo machine and ink cartridges; visible bold geometric body art | ice blue `#9FE9FF`, graphite, small violet | `[0.20,0.02,0.60,0.42]` |

Set `cn/title` from `data/characters.json`. Apply this shared `forbid` list to all eight records:

```json
["photorealism", "3d render", "chibi", "low-poly mannequin", "generic bodysuit", "same face as another character", "tiny unreadable profession prop", "copied anime character", "text", "logo", "watermark"]
```

- [ ] **Step 4: Validate JSON and commit references plus manifest**

Run:

```bash
jq -e '.characters | length == 8' assets/characters/manifest.json
jq -e '[.characters[].idx] == [0,1,2,3,4,5,6,7]' assets/characters/manifest.json
```

Expected: both commands return `true`. Commit the eight references and manifest using the Lore protocol.

### Task 2: Lock the asset contract with a failing validator

**Files:**
- Create: `tools/art/verify_character_assets.gd`

- [ ] **Step 1: Validate the manifest against gameplay identity**

Load `assets/characters/manifest.json` and `data/characters.json`. Require exactly eight records, dense indices 0–7, exact `cn/title` equality at each index, no empty identity fields, and no placeholder copy.

- [ ] **Step 2: Validate final file geometry**

Use this exact contract:

```gdscript
const IDS := ["dj", "magician", "boxer", "bartender", "seer", "drummer", "rapper", "tattooist"]
const FILES := {
	"portrait.png": Vector2i(1536, 2048),
	"avatar.png": Vector2i(512, 512),
	"walk.png": Vector2i(1024, 128),
	"dance.png": Vector2i(1024, 128),
}
```

For `walk.png` and `dance.png`, require at least one transparent pixel and at least one non-transparent pixel in every 128×128 frame. Require `prompt.json` to contain matching `id`, non-empty `portrait_prompt`, `walk_prompt`, `dance_prompt`, revisions >= 1, and three lowercase SHA-256 hashes.

- [ ] **Step 3: Run the validator and verify RED**

```bash
godot --headless --path . --script res://tools/art/verify_character_assets.gd
```

Expected: exit 1 listing the missing final assets for all eight IDs.

- [ ] **Step 4: Commit the validator**

Commit only `tools/art/verify_character_assets.gd`; record the expected RED state in `Tested:`.

### Task 3: Implement deterministic portrait, avatar, and sprite-sheet processing

**Files:**
- Create: `tools/art/build_character_assets.gd`

- [ ] **Step 1: Normalize portraits without distortion**

For each `assets/characters/source/<id>_portrait.png`, center-crop to 3:4, resize to 1536×2048 with Lanczos filtering, and save as `portrait.png`. Do not stretch width or height independently. Support `--stage=portrait`, `--stage=walk`, `--stage=dance`, and `--stage=all`; default to `all`.

- [ ] **Step 2: Crop avatars from manifest coordinates**

Interpret `avatar_crop` as normalized `[x, y, width, height]` against the normalized portrait. Crop that region, center-crop to square if required, resize to 512×512, and save as `avatar.png`.

- [ ] **Step 3: Pack 4×2 animation source sheets**

For each walk/dance source image:

1. divide the image into four equal columns and two equal rows;
2. crop 3% from each cell edge to remove gutters;
3. remove pixels within RGB distance 42 of chroma key `#00FF66` and reduce alpha linearly until distance 70;
4. trim transparent bounds;
5. resize the character to fit within 118×122 while preserving aspect ratio;
6. anchor feet at y=124 and center x=64 in a transparent 128×128 frame;
7. place frames left-to-right in a 1024×128 output sheet.

Reject any empty frame or a frame whose opaque bounds touch the top, left, or right edge.

- [ ] **Step 4: Run the builder and verify the expected missing-source failure**

```bash
godot --headless --path . --script res://tools/art/build_character_assets.gd
```

Expected before generation: exit 1 listing 24 missing source images: eight portraits, eight walk sheets, and eight dance sheets.

- [ ] **Step 5: Commit the builder**

Commit only `tools/art/build_character_assets.gd` with the Lore protocol.

### Task 4: Generate and approve the eight portrait masters

**Files:**
- Create: `assets/characters/source/<id>_portrait.png` for all eight IDs.
- Create/update: `assets/characters/<id>/prompt.json` for all eight IDs.

- [ ] **Step 1: Read the ImageGen skill before generating**

Use the matching `candidate_<id>.png` as a reference for each character. The selected panel is authoritative; the other two panels are only style context.

- [ ] **Step 2: Generate each portrait with the shared prompt contract**

```text
Create one original full-body 2D cyberpunk anime profession character for Sync5: {cn}, title “{title}”.
Identity: {identity_contract}.
Use the {selected_panel} design from the supplied three-panel reference as the starting silhouette, then refine it into a unique production model sheet pose.
Visual language: sharp variable-width black contour, hard cel-shaded blocks, graphic anatomy, saturated neon accents, expressive face, readable hands and profession prop, full body from hair to footwear, clean deep-black studio background, no scenery.
The character must remain identifiable at 150×196 through silhouette, palette, and prop. Original design only; do not copy a specific existing anime character.
Avoid: {forbid}.
No text, logo, frame, UI, or watermark.
```

Generate each portrait separately. Reject cropped feet, hidden profession props, same-face drift, or a pose too wide for a 3:4 crop. Copy the accepted image to `assets/characters/source/<id>_portrait.png` and record prompt/revision/hash.

- [ ] **Step 3: Build portrait/avatar outputs and review at actual size**

Run `godot --headless --path . --script res://tools/art/build_character_assets.gd -- --stage=portrait`, then inspect each `portrait.png` at 150×196 and each `avatar.png` at 64×64. Adjust only the manifest crop when the avatar framing is wrong; regenerate the portrait only for identity or silhouette failure.

- [ ] **Step 4: Commit the eight portrait sources, portraits, avatars, and prompt records**

Commit 32 files: eight raw sources, eight portraits, eight avatars, and eight prompt records.

### Task 5: Generate the eight walk source sheets

**Files:**
- Create: `assets/characters/source/<id>_walk.png` for all eight IDs.
- Update: `assets/characters/<id>/prompt.json` for all eight IDs.

- [ ] **Step 1: Use each accepted portrait as the only identity reference**

Do not reference another character's portrait. Keep head, hair, clothing silhouette, palette, body type, and profession prop locked.

- [ ] **Step 2: Generate a 4×2 sheet with this exact prompt**

```text
Using the supplied approved portrait as the exact identity reference, create an eight-frame right-facing walk cycle for this same character.
Layout: clean 4 columns × 2 rows, chronological frames left-to-right then top-to-bottom, equal cell size, full body visible in every cell, consistent camera, scale, face, hair, clothes, palette, and profession prop.
Animation: contact, down, passing, up, opposite contact, opposite down, opposite passing, opposite up. Strong readable key poses for a 128×128 game sprite; simplify small costume details but never change the outfit or body type.
Flat chroma-key background exactly #00FF66, no shadows, no floor, no borders, no labels, no numbers, no text, no watermark.
```

Reject sheets with merged cells, fewer than eight figures, inconsistent scale, left-facing frames, or changed outfits.

- [ ] **Step 3: Pack and inspect all walk sheets**

Run `godot --headless --path . --script res://tools/art/build_character_assets.gd -- --stage=walk`. Inspect every frame at 128×128 and as a looping animation. The full validator remains RED only for dance files. At roughly 54×70, profession and individual silhouette must still be distinguishable.

- [ ] **Step 4: Commit walk sources, final sheets, and updated prompt records**

Commit 24 files: eight raw walk sheets, eight final walk sheets, and eight prompt records.

### Task 6: Generate the eight dance source sheets

**Files:**
- Create: `assets/characters/source/<id>_dance.png` for all eight IDs.
- Update: `assets/characters/<id>/prompt.json` for all eight IDs.

- [ ] **Step 1: Generate profession-specific victory motion**

Use this exact shared prompt, substituting the character-specific action:

```text
Using the supplied approved portrait as the exact identity reference, create an eight-frame looping victory dance for this same character.
Profession action: {profession_action}.
Layout: clean 4 columns × 2 rows, chronological frames left-to-right then top-to-bottom, equal cell size, full body visible, consistent camera, scale, face, hair, clothes, palette, and profession prop.
The loop must have a clear anticipation, two strong celebration keys, and a return pose. Readable at 128×128; simplify tiny costume details without changing identity.
Flat chroma-key background exactly #00FF66, no shadows, no floor, no borders, no labels, no numbers, no text, no watermark.
```

Use these exact actions:

- DJ: spin one deck control and throw the free hand upward on the beat.
- Magician: fan projected cards, snap them into one glowing card, then bow.
- Boxer: two compact victory jabs followed by raised gloves.
- Bartender: toss and catch the shaker, then present a glowing drink.
- Seer: sweep probability arcs into a bright crystal pulse.
- Drummer: strike a fast fill on waist pads and finish with crossed sticks.
- RAPPER: bounce low, punch one hand toward the crowd, then lift the microphone.
- Tattooist: spin the tattoo machine safely, reveal a glowing geometric motif, then nod.

- [ ] **Step 2: Pack and inspect all dance sheets**

Run `godot --headless --path . --script res://tools/art/build_character_assets.gd -- --stage=dance`, then run the validator. Reject identity drift, unsafe tool motion, frame order breaks, and any motion that looks like the walk cycle with raised arms.

- [ ] **Step 3: Commit dance sources, final sheets, and updated prompt records**

Commit 24 files: eight raw dance sheets, eight final dance sheets, and eight prompt records.

### Task 7: Build the final contact sheet and complete verification

**Files:**
- Create: `tools/art/character_contact_sheet.gd`
- Create: `assets/characters/contact-sheet.png`
- Modify: `assets/design/README.md`

- [ ] **Step 1: Render a two-row character review sheet**

Create a 2048×1152 sheet. For each of eight columns, show the 150×196 portrait preview, 96×96 avatar, eight walk frames, and eight dance frames. Row one contains DJ through bartender; row two contains seer through tattooist. Label with `cn/title` from the manifest, not generated text.

- [ ] **Step 2: Run automated validation**

```bash
godot --headless --path . --script res://tools/art/verify_character_assets.gd
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/runner.gd
git diff --check
```

Expected: eight exact roster entries; 32 final files; 24 raw sources; all image dimensions exact; every animation frame contains both transparent and opaque pixels; character gameplay tests remain green.

- [ ] **Step 3: Perform visual acceptance**

At 150×196, all eight professions must be identifiable without names. At 54×70, no two characters may share the same head/torso silhouette or primary palette. Across portrait, avatar, walk, and dance, each identity must retain the same face, hair, body type, clothes, and profession prop.

- [ ] **Step 4: Document asset ownership and commit**

Update `assets/design/README.md` with the manifest, source/final directory meanings, regeneration commands, and the explicit note that runtime integration is a separate future task. Commit the contact sheet, contact-sheet tool, and README update with the Lore protocol.
