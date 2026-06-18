# Plan: root-cause fix for short_id ↔ acts-as-taggable incompatibility

## Problem
Node link/backlink tracking uses `acts_as_taggable_on :links, :inclusions`, where each
tag name is a **node short_id**. Short_ids are case-sensitive identifiers drawn from a
~716-char Unicode alphabet (`short_id` gem, `lib/id_chars.rb`), so `dr` and `dR` are
distinct nodes.

acts-as-taggable defaults to **case-insensitive** tag matching. Two failure modes result:

1. **Hard crash (already mitigated):** `İ` (U+0130) folds via `unicode_downcase` to a
   2-codepoint string, breaking the `LOWER(name)=LOWER(?)` lookup → a blank Tag → save
   fails with "Tag can't be blank". 12 nodes were affected; we remapped them to ASCII
   short_ids and added a guard in `Node#set_short_id`
   (`PROBLEMATIC_SHORT_ID_CHARS`). This plan supersedes the need for that guard but it can
   stay as defense-in-depth.
2. **Silent corruption (NOT yet fixed):** `dr` and `dR` fold to the same tag, so the
   links/inclusions graph conflates distinct nodes. **Audit on 2026-06-18: 3,592 collision
   groups out of 8,938 short_ids** — roughly half the link graph is affected.

### Root cause
The defect is the tagging layer's case-insensitivity, not the short_ids. Short_ids are valid
case-sensitive identifiers.

### Gem mechanics (acts-as-taggable-on 8.1.0, vendored)
`lib/acts_as_taggable_on/tag.rb`:
- `named_any` (used by `find_or_create_all_with_like_by_name`):
  - `strict_case_match=false` → `LOWER(name)=LOWER(?)` on a pre-`unicode_downcase`d value.
  - `strict_case_match=true`  → `name = ?` (exact; `BINARY` only on MySQL).
- `comparable_name` (dedup): `strict` → `str` unchanged; else `unicode_downcase(str)`.
Setting `ActsAsTaggableOn.strict_case_match = true` makes both exact + Unicode-safe.

### Schema facts (no change needed)
- `tags.name` has a plain case-sensitive btree unique index (`index_tags_on_name`), so
  `dr` and `dR` can coexist as separate rows. (If it were a `LOWER(name)` functional index
  this plan would also need an index migration — it is NOT.)
- Postgres adapter. Only taggable model is `Node` (`:links`, `:inclusions`); both contexts
  are short_id-based, so a *global* strict setting has no human-facing-tag downside.

## Decision
**Option A: enable `strict_case_match` globally + rebuild the tag graph.** Reject Option B
(regenerate short_id alphabet) as primary — it would rewrite every short_id, every
`[text](short_id)` link, and break external short_id URLs. Keep a narrow future track:
switch only the *new-node* generator to a clean unambiguous alphabet (no retroactive change).

## Execution steps (fresh context)

Pre-flight:
- Run against prod via the `DATABASE_URL` in `~/.config/fish/config.fish` (zup/zdown use it).
- **Back up first:** `pg_dump` the `tags` and `taggings` tables (the rebuild rewrites them).
- Confirm 0 nodes still have problematic short_ids:
  `User.find(1).nodes.where("short_id LIKE '%İ%'").count` → expect 0.

1. **Config flag.** Create `config/initializers/acts_as_taggable_on.rb`:
   ```ruby
   ActsAsTaggableOn.strict_case_match = true
   ```
   (Do NOT use `force_binary_collation` — that's MySQL-oriented.)

2. **Audit / snapshot (read-only).** Record before-state for verification:
   - collision groups: group `short_id`s by `mb_chars.downcase` and count groups with >1
     distinct value (expect ~3,592).
   - current `ActsAsTaggableOn::Tag.count` and link/inclusion `Tagging` counts.

3. **Rebuild taggings under strict matching.** One-time rake task
   (e.g. `vault:rebuild_link_tags`):
   - For each `Node`, recompute tags by re-running the tagging callbacks. Simplest:
     `node.save!` (before_save runs `tag_links`/`tag_inclusions`; `save_tags` reconciles —
     creating the now-distinct tags and fixing associations). No İ failures now.
   - Note: `revalidate_cache` (after_save) is a no-op when `REVALIDATION_TOKEN` is unset, so
     no external calls fire. Re-saving bumps `updated_at` on all nodes (one-time; next
     `zdown` will re-export everything once — acceptable).
   - Alternative if updated_at churn is undesirable: delete `:links`/`:inclusions` taggings,
     then rebuild taggings directly from `node.get_links` / `node.get_inclusions` without a
     full `save`. More code; only do if the updated_at bump matters.
   - After rebuild: clean orphaned tags: `ActsAsTaggableOn::Tag.where(taggings_count: 0).delete_all`
     (verify `taggings_count` is accurate first, or recompute).

4. **Tests.** Add `spec/models/node_spec.rb` cases:
   - Two nodes with short_ids differing only by case (`dr`, `dR`) → a node linking to both
     produces two distinct link tags (regression for the collision bug).
   - A node whose short_id contains `İ` can be linked without error (regression for crash),
     OR assert the `set_short_id` guard prevents `İ` short_ids.

5. **Full verification.**
   - `bundle exec rspec` (models + services).
   - `rake vault:sync` end-to-end → expect Created/Updated/Failed all sane, **Failed: 0**.
   - Spot-check backlinks for a known collision pair resolve to the correct distinct nodes.

## Risks & rollback
- The rebuild rewrites tags/taggings. Rollback = restore the `tags`/`taggings` backup and
  remove the initializer.
- Global flag affects all tagging; safe here because only `Node` link/inclusion (short_id)
  tags exist. Re-confirm no new human-facing taggable models were added before running.
- Re-saving all nodes is heavy but one-time; run off-peak.

## Future (optional, separate): cleaner short_id alphabet
For NEW nodes only (non-retroactive), migrate the generator off the fragile Unicode alphabet
to e.g. Crockford base32 / base58 (unambiguous, normalization-stable, URL/copy-paste safe).
This addresses NFC/NFD and visual-confusion fragility independent of the tagging fix. Existing
short_ids stay as-is. Lower priority.
