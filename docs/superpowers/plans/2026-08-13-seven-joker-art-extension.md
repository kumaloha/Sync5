# Seven Joker Art Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add production-ready five-file art bundles for `duo`, `duet`, `triad`, `triplebill`, `backer`, `bench`, and `boxseats` while preserving the existing 60-card visual system byte-for-byte.

**Architecture:** Copy only the seven approved manifest records from the user's main worktree, extend the existing deterministic validator and runtime renderer from 60 to 67 IDs, generate one chroma-key central totem per new ID with the built-in image tool, then reuse the existing Godot and HTML pipelines for derived assets. Verification separates deterministic asset checks from a seven-card visual contact-sheet review.

**Tech Stack:** Godot 4.6 GDScript, JSON manifests, built-in ImageGen, chroma-key removal helper, headless Chrome card renderer, FFmpeg contact sheet.

---

### Task 1: Extend the immutable Joker asset catalog

**Files:**
- Modify: `tools/art/verify_joker_assets.gd`
- Modify: `tools/art/build_joker_runtime_art.gd`
- Modify: `assets/jokers/manifest.json`

- [ ] **Step 1: Make the validator expect the seven approved IDs**

Append this exact sequence to `IDS` in `tools/art/verify_joker_assets.gd`:

```gdscript
"duo", "duet", "triad", "triplebill", "backer", "bench", "boxseats",
```

- [ ] **Step 2: Run the validator and verify RED**

Run:

```bash
godot --headless --log-file /tmp/sync5-joker-seven-red.log --path . --script res://tools/art/verify_joker_assets.gd
```

Expected: non-zero exit with `manifest.json.cards must contain exactly 67 records, found 60` and missing-resource errors for the seven IDs.

- [ ] **Step 3: Append only the seven approved manifest records**

Copy S-53 through S-59 from `/Users/kuma/Projects/Sync5/assets/jokers/manifest.json` into this branch's `assets/jokers/manifest.json`, preserving this order:

```text
duo, duet, triad, triplebill, backer, bench, boxseats
```

Do not copy the two rarity edits or any other dirty-main changes.

- [ ] **Step 4: Extend the runtime builder count contract**

In `tools/art/build_joker_runtime_art.gd`, replace the literal 60-card expectation with:

```gdscript
const EXPECTED_CARD_COUNT := 67
```

and use it in `_load_manifest()`:

```gdscript
if cards.size() != EXPECTED_CARD_COUNT:
    _error("%s.cards must contain exactly %d records, found %d" % [
        _display_path(MANIFEST_PATH), EXPECTED_CARD_COUNT, cards.size(),
    ])
```

- [ ] **Step 5: Verify the manifest phase is GREEN apart from absent generated files**

Run the validator again. Expected: no count, order, code, duplicate-ID, or record-field errors; only absent source/runtime/card/preview/prompt errors remain for the seven new IDs.

- [ ] **Step 6: Commit the catalog extension**

Commit only the three files above with a Lore-format message recording the 67-card constraint and the still-missing generated assets.

### Task 2: Generate the seven central source totems

**Files:**
- Create: `assets/jokers/source/joker_duo.png`
- Create: `assets/jokers/source/joker_duet.png`
- Create: `assets/jokers/source/joker_triad.png`
- Create: `assets/jokers/source/joker_triplebill.png`
- Create: `assets/jokers/source/joker_backer.png`
- Create: `assets/jokers/source/joker_bench.png`
- Create: `assets/jokers/source/joker_boxseats.png`
- Create: seven matching files under `assets/jokers/prompts/`

- [ ] **Step 1: Generate one built-in ImageGen result per ID**

Use `assets/jokers/source/joker_crescendo.png`, `joker_chorus.png`, `joker_sponsor.png`, and `joker_rehearsal.png` only as high-level material and silhouette references. Every prompt uses: `stylized-concept`, compact centered totem, hard-edged black glass and metal, cyan rim, rarity accent, perfectly flat `#00ff00` background, no shadow, no reflection, no text, no card frame, no watermark.

Distinct subjects:

```text
duo: two anthropomorphic playing-card silhouettes facing each other and sharing one central upright microphone; exactly two cards.
duet: exactly two thick cyan-violet sound ribbons intertwining upward as a compact double helix.
triad: exactly three luminous instrument strings converging into one bold triangular chord node.
triplebill: exactly three side-by-side stage-light pillars supporting one blank angular marquee; no writing.
backer: one dark-gloved hand extending one blank cheque-like slab with a single faceted diamond token toward a curtain edge.
bench: one compact waiting bench holding several dark card silhouettes while exactly one high-card silhouette stands upright and glows.
boxseats: one ornate box-seat arch containing exactly three face-card silhouettes overlooking a tiny abstract stage aperture.
```

- [ ] **Step 2: Copy each raw result into project staging**

Save each raw generated PNG to `tmp/imagegen/joker_<id>-chroma.png`, retaining the returned original path in its final prompt JSON.

- [ ] **Step 3: Remove chroma key into the final source paths**

Run the installed helper separately for all seven files with `--auto-key border --soft-matte --transparent-threshold 12 --opaque-threshold 220 --despill`. Resize deterministically to exactly 1024×1024 only if ImageGen returned another square size.

- [ ] **Step 4: Inspect all seven transparent sources**

Check alpha channel, transparent corners, subject coverage, recognizable object count, crisp edges, no green fringe, no text, and no watermark. Regenerate only a failing ID with one targeted prompt correction.

- [ ] **Step 5: Write reproducibility records**

For each ID, create `assets/jokers/prompts/joker_<id>.json` containing `id`, exact `prompt`, `revision`, `source_sha256`, `tool_mode: "built-in"`, `reference`, and `raw_codex_path` in the same schema as existing prompt records.

### Task 3: Derive runtime art and full card renders

**Files:**
- Create: seven `assets/jokers/joker_<id>.png` files
- Create: seven `assets/jokers/cards/joker_<id>.png` files
- Create: seven `assets/jokers/previews/joker_<id>.png` files

- [ ] **Step 1: Build the runtime strips**

Run:

```bash
godot --headless --log-file /tmp/sync5-joker-seven-build.log --path . --script res://tools/art/build_joker_runtime_art.gd -- --ids=duo,duet,triad,triplebill,backer,bench,boxseats
```

Expected: seven `saved assets/jokers/joker_*.png` lines and zero errors.

- [ ] **Step 2: Render complete cards and previews**

Run:

```bash
tools/art/render_joker_cards.sh duo,duet,triad,triplebill,backer,bench,boxseats
```

Expected: seven 1240×1376 card PNGs and seven 155×172 preview PNGs.

- [ ] **Step 3: Verify exact dimensions**

Use `sips -g pixelWidth -g pixelHeight` on all 28 generated PNGs. Expected source 1024×1024, runtime 1024×400, card 1240×1376, preview 155×172.

### Task 4: Run visual and deterministic QA

**Files:**
- Create: `assets/jokers/review-new-seven.png`
- Create: `.omx/state/joker-seven-assets/ralph-progress.json`

- [ ] **Step 1: Build the seven-card contact sheet**

Use FFmpeg's `xstack` filter to place the seven 155×172 previews in one horizontal row on a dark neutral background without modifying the previews.

- [ ] **Step 2: Run visual-verdict against existing approved cards**

Compare the contact sheet and individual new cards to approved `joker_crescendo.png`, `joker_chorus.png`, `joker_sponsor.png`, and `joker_rehearsal.png`. Pass threshold is 90; persist JSON with score, verdict, category match, concrete differences, suggestions, reasoning, and next actions.

- [ ] **Step 3: Run the 67-card asset validator**

Run:

```bash
godot --headless --log-file /tmp/sync5-joker-seven-verify.log --path . --script res://tools/art/verify_joker_assets.gd
```

Expected: `joker asset manifest OK: 67 records` and exit 0.

- [ ] **Step 4: Prove original 60 assets did not drift**

Compare hashes for existing `source`, runtime, `cards`, `previews`, and `prompts` files against commit `7bdd468^`. Expected: no changed path for the original 60 IDs.

- [ ] **Step 5: Run project regression tests**

Run:

```bash
godot --headless --log-file /tmp/sync5-joker-seven-tests.log --path . --script res://tests/runner.gd
```

Expected: 948 or more passed, 0 failed.

### Task 5: Commit and present the finished bundle

**Files:**
- Commit all files created or modified by Tasks 1–4, excluding `.godot/`, generated `.uid` noise, and temporary chroma sources.

- [ ] **Step 1: Review the final diff**

Confirm the diff contains exactly seven manifest records, two deterministic tool changes, 35 final asset files, one contact sheet, seven prompt records counted within those assets, the plan, the approved spec, and the visual-verdict state. Confirm no unrelated main-worktree changes appear.

- [ ] **Step 2: Commit with Lore trailers**

Record the visual inheritance constraint, rejected independent-poster approach, tests, asset validator, visual-verdict score, and any remaining non-fatal environment warnings.

- [ ] **Step 3: Show the contact sheet to the user**

Return the saved branch, full contact sheet, card directory, generated prompts, deterministic verification evidence, and no claim of push unless a push actually occurred.
