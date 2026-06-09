# updateEventRow — keyed sparse merge

Keyed sibling of `updateTableRow`. Merges listed char-code keys into an EXISTING
keyed (char-code) Firestore doc selected by `search`. Sparse — only the listed
keys change; never blank-prefills. Use `addToEvent` for inserts (0-match → skip).

## DSL

```
<tableDocId>//<subColl>⭘tablevid◼<TABLE_VID>⭘search◼<clause>⭘<key>◼<value>…
```

- `search` clause: `key★value` (single), or `key★value☆key★value` (AND).
  `★`=separator[3], `☆`=separator[6].
- Body keys are char-codes (`is`, `os`, `st`, …), same as `addToEvent`.
- Multiple statements chain with `◆`; may interleave with `updateTableRow`.

## Pipeline

`component['updateEventRow']` → `saveSend` (decode + placeholder/screenTx pre-pass)
→ `history[14]` 5th `⬤`-segment → `historySync` → `writeUpdateEventRow`.

Path = `MobileTable/<tablevid>/tables/<tableDocId>/<subColl>` (via
`eventCollectionPath`). Body + search values resolve through `resolveValueTokens`
(`◀N▶` system, `◁N▷` form). Search values type-coerced by `_parseSearchValue`.

## Match semantics

- 1 match → `set(patch, merge:true)`.
- 0 → skip + log (no create).
- >1 → error + skip (no partial write); uniqueness is corrupt.

## Example — attendance correction (this app)

```
84214220504259//workforce⭘tablevid◼20342033315492⭘search◼vid★<vid>⭘os◼◁1▷⭘is◼◁2▷
```

Worker `vid` is globally unique → single-condition search matches exactly one doc.

See `docs/superpowers/plans/2026-06-09-kehadiran-card.md` and
`2026-06-04-updateEventRow-design.md`.
