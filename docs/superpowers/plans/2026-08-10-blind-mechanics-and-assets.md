# Blind Mechanics and Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the approved 8/8/8 + fixed Rush + 4 surprise-boon Blind design into validated game data and working runtime rules, and archive the approved Blind card catalog under `assets/design`.

**Architecture:** Keep punitive Blind faces in `data/faces.json` and introduce `data/boons.json` for finale-only positive effects. `SectionMod` remains the data facade for pressure rules; a focused `BlindBoon` facade owns boon lookup and rolling. Engine-free state and rule enforcement remain in `Run`, `Phrase`, `Beat`, and `Settle`; the view only supplies clock position and renders the already-decided face/boon.

**Tech Stack:** Godot 4.6, GDScript, JSON data tables, the existing headless test runner, and repository-native HTML visual assets.

---

### Task 1: Lock the new data contracts with failing tests

**Files:**
- Modify: `tests/t_db.gd`
- Modify: `tests/t_face.gd`
- Create: `tests/t_boon.gd`
- Modify: `tests/runner.gd`

- [x] **Step 1: Add assertions for the exact 8/8/8/1 pressure pools**

```gdscript
t.eq(SectionMod.pool_for(0).size(), 8, "round 1 has eight faces")
t.eq(SectionMod.pool_for(1).size(), 8, "round 2 has eight faces")
t.eq(SectionMod.pool_for(2).size(), 8, "round 3 has eight faces")
t.eq(SectionMod.pool_for(3), ["rush"], "round 4 pressure is fixed Rush")
```

- [x] **Step 2: Add assertions for an independent four-boon table**

```gdscript
t.eq(BlindBoon.roster().size(), 4, "four finale boons are configured")
t.check(BlindBoon.by_id("doubleset") != null, "doubleset is configured")
t.check(BlindBoon.by_id("spotlight") != null, "spotlight is configured")
t.check(BlindBoon.by_id("afterglow") != null, "afterglow is configured")
t.check(BlindBoon.by_id("encore") != null, "encore is configured")
```

- [x] **Step 3: Run the suite and verify RED**

Run: `godot --headless --path . --script res://tests/runner.gd`

Expected: FAIL because the new roster, boon loader, and new parameter whitelist do not exist.

### Task 2: Implement the strict data layer

**Files:**
- Modify: `data/faces.json`
- Create: `data/boons.json`
- Modify: `core/db.gd`
- Modify: `core/modifier.gd`
- Create: `core/blind_boon.gd`

- [x] **Step 1: Replace active face tiers with the approved final pools**

Retain `unplugged`, `static`, `rotation`, `cover`, and `freshsheet` without `tier` or active `proof`, then add every approved face with its `tier`, `proof`, optional `tape_required`, and data-only `params`.

- [x] **Step 2: Add the independent boon table**

```json
{
  "boons": [
    {"id":"doubleset","name":"Double Set","cn":"双响","fx":"Replay score at half power","params":{"score_replay_factor":0.5}},
    {"id":"spotlight","name":"Spotlight","cn":"聚光","fx":"Best five of six cards","params":{"spotlight_cards":1}},
    {"id":"afterglow","name":"Afterglow","cn":"余响","fx":"Add ten percent previous score","params":{"previous_raw_factor":0.1}},
    {"id":"encore","name":"Encore","cn":"返场","fx":"First discarded hand batch still scores","params":{"ghost_first_discard":1}}
  ]
}
```

- [x] **Step 3: Extend strict validators and data facades**

Add `DB.boons()`, `DB.validate_boons()`, `tape` as a proof channel, `tape_required` as an allowed face field, and explicit parameter keys grouped by whether they affect settlement.

- [x] **Step 4: Run the data and roster tests and verify GREEN**

Run: `godot --headless --path . --script res://tests/runner.gd`

Expected: the new data-contract assertions pass; behavior assertions added in later tasks are not present yet.

### Task 3: Implement action, card-flow, and section-state Blind rules test-first

**Files:**
- Modify: `tests/t_phrase.gd`
- Modify: `tests/t_run.gd`
- Modify: `core/deck.gd`
- Modify: `core/phrase.gd`
- Modify: `core/run.gd`
- Modify: `core/beat.gd`

- [x] **Step 1: Add failing tests for action limits and sealed cards**

Cover `onetake`, `oneswap`, `throttle`, `switchtrack`, `handseal`, `doubleseal`, `redlight`, and `wetink` with successful first actions and rejected prohibited actions.

- [x] **Step 2: Add failing tests for card flow and section resources**

Cover low-rank refill filtering, `blackout`, the twelve-card `ration` budget, `trilogy` progress as an additional clear condition, request goals without consecutive repetition, and cache age identity.

- [x] **Step 3: Implement the minimum shared state and rule checks**

Use object identity for initial-cache, sealed-hand, sealed-cache, and newly cached cards. Keep cache ages in run-owned shared metadata so “oldest” survives phrase boundaries. Keep request choice and section counters on `Run` and configure each `Phrase` in `Beat.begin()`.

- [x] **Step 4: Run the phrase/run tests and verify GREEN**

Run: `godot --headless --path . --script res://tests/runner.gd`

Expected: all action and cross-phrase state tests pass.

### Task 4: Implement scoring pressure and finale boons test-first

**Files:**
- Modify: `tests/t_settle.gd`
- Modify: `tests/t_run.gd`
- Modify: `core/settle.gd`
- Modify: `core/beat.gd`
- Modify: `core/run.gd`
- Modify: `core/phrase.gd`

- [x] **Step 1: Add failing tests for request and Patch In**

Verify a missed request applies exactly the configured factor, and `patchin` halves settlement Joker chips/multiplier/bonus contributions unless the final hand contains an object from the phrase-start cache snapshot.

- [x] **Step 2: Add failing tests for all four boons**

Verify Double Set adds 50% without a second Joker call, Spotlight evaluates six cards while exposing no sixth action slot, Afterglow reads only the previous raw score, and Encore adds a cloned first-discard ghost without firing discard hooks twice.

- [x] **Step 3: Implement scoring transforms in one settlement path**

Store `raw_score` before boon additions, apply one boon after normal settlement, and update `Run.previous_raw_score` exactly once. Do not route boon additions through Joker or phrase-end hooks.

- [x] **Step 4: Verify the six-second invariant**

```gdscript
for boon_id in BlindBoon.ids():
    r.run_boon = boon_id
    t.eq(r.phrase_duration(), 6.0, "%s never changes Rush timing" % boon_id)
```

- [x] **Step 5: Run the settlement/run tests and verify GREEN**

Run: `godot --headless --path . --script res://tests/runner.gd`

Expected: all pressure and boon scoring tests pass.

### Task 5: Connect clock gates, reveal, and approved color responsibility

**Files:**
- Modify: `view/phrase.gd`
- Modify: `view/hand.gd`
- Modify: `view/intro.gd`
- Modify: `view/shop.gd`
- Modify: `view/widgets.gd`
- Modify: `tests/t_hand.gd`

- [x] **Step 1: Add failing view-level assertions**

Lock the rule that every Blind uses the magenta accent, while finale boons use gold; lock separate discard/swap availability in the hand view model.

- [x] **Step 2: Gate late discard and swap using the real view clock**

Use `SectionMod.discard_lock_last()` and `swap_lock_last()` in input handlers and refresh the relevant controls once when a gate closes. Core code remains clock-free.

- [x] **Step 3: Reveal the selected boon only on entering round four**

Pass `BlindBoon.by_id(run.boon())` into the intro/current Blind card and section shop board; never include it in previews of earlier rounds.

- [x] **Step 4: Use magenta for all pressure Blind frames**

Make `Widgets.StageCard.accent_for()` return `StageTheme.PINK` for all four rounds; use gold only for the positive boon label.

- [x] **Step 5: Run headless tests and verify GREEN**

Run: `godot --headless --path . --script res://tests/runner.gd`

Expected: all view-model and full-suite tests pass.

### Task 6: Archive the approved visual catalog

**Files:**
- Create: `assets/design/blind_card_ui.html`
- Modify: `assets/design/README.md`
- Modify: `docs/superpowers/specs/2026-08-10-joker-blind-visual-system-design.md`

- [x] **Step 1: Add the approved interactive Blind deck artifact**

Store the reviewed fragment with 118×176 cards, 68×68 fingerprints, 43px summaries, magenta pressure frames, and gold finale boons.

- [x] **Step 2: Make asset ownership explicit**

Document `joker_blind_visual_system.html` as the Joker/general-language catalog and `blind_card_ui.html` as the authoritative final Blind deck catalog.

- [x] **Step 3: Render the repository asset and compare it to the approved preview**

Run the bundled visualization renderer against `assets/design/blind_card_ui.html`, then inspect the standalone page at desktop and 360px widths.

Expected: exact 118×176 CSS size, no horizontal overflow, all pressure frames magenta, finale rewards gold.

### Task 7: Final verification and branch review

**Files:**
- Review all modified files

- [x] **Step 1: Run the complete headless suite**

Run: `godot --headless --path . --script res://tests/runner.gd`

Expected: zero failed tests.

- [x] **Step 2: Run import/build validation**

Run: `godot --headless --path . --editor --quit`

Expected: exit code 0 with no parse errors.

- [x] **Step 3: Review the branch diff against `design/blinds.md`**

Confirm all 29 configured entries, retired faces have no tier, every new parameter is validated and read, all boons preserve six seconds, and the visual asset lives under `assets/design`.

- [x] **Step 4: Commit with the repository Lore protocol**

Commit only the implementation and asset files after fresh verification, recording tested commands and known Tape/manual-play gaps in trailers.
